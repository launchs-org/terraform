# gVisor と Cilium の設定と検証

Talos Linux 上で、gVisor(`runsc`)のサンドボックスから Service(`*.svc.cluster.local`)に通信できるようにするまでの設定と、検証の記録です。
目的は、他人が持ち込んだコード(ビルドとアプリ)を、ホストのカーネルに直接触らせずに動かすことです。

## 設定の概要

| 層 | 設定 | 場所 |
|---|---|---|
| Talos 拡張 | `siderolabs/gvisor`(あわせて Longhorn 用に `iscsi-tools`、`util-linux-tools`) | Image Factory のスキーマティック → `talos/worker-extensions.yaml` の `install.image` |
| containerd | `runsc` ランタイムの登録 | `talos/worker-extensions.yaml` の `machine.files`(`/etc/cri/conf.d/20-customization.part`) |
| Kubernetes | `RuntimeClass: gvisor`(handler `runsc`) | `talos/manifests/runtimeclass-gvisor.yaml` |
| Cilium | `socketLB.hostNamespaceOnly=true` | Helm の値 |

使い方は、Pod に `runtimeClassName: gvisor` を付けるだけ。

## 手順

### 1. 拡張入りイメージを作る

```bash
cat > schematic.yaml <<'EOF'
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
      - siderolabs/gvisor
EOF
curl -X POST --data-binary @schematic.yaml https://factory.talos.dev/schematics   # → {"id":"<schematic-id>"}
```

インストーラは `factory.talos.dev/installer/<schematic-id>:v1.13.2`。

### 2. worker に適用する(再起動あり)

新規ノードでは `talos/worker-extensions.yaml` を Terraform のパッチとして使う。既存ノードの更新は、[talos-k8s.md](talos-k8s.md) の「ノードの更新」に従い、`install.image` だけを変える(設定を丸ごと重ねると二重定義でブートが止まる)。
適用後、`talosctl get extensions` に `iscsi-tools` / `util-linux-tools` / `gvisor` が出て、ノードの `/usr/local/bin` に `runsc` と `containerd-shim-runsc-v1` がある。

### 3. RuntimeClass を作る

```bash
kubectl apply -f talos/manifests/runtimeclass-gvisor.yaml
```

### 4. Cilium の設定

gVisor は独自のネットワークスタック(netstack)を持ち、`connect()` ではなくパケットを直接送る。
そのため、Cilium の socket-LB(`connect()` の時点で ClusterIP を書き換える方式)が効かず、Service の IP に届かない。
Pod の中では socket-LB を使わず、パケット単位で Service を変換させる。

```bash
helm upgrade cilium cilium/cilium -n kube-system --reuse-values --set socketLB.hostNamespaceOnly=true
kubectl -n kube-system rollout restart ds/cilium     # ★必須。下記の「落とし穴」を参照
```

ホスト名前空間(kubelet / containerd が Harbor の ClusterIP を引く経路)の socket-LB は維持される。

#### 反映の確認

```bash
kubectl -n kube-system exec <cilium-pod> -c cilium-agent -- cilium-dbg config -a | grep BPFSocketLBHostnsOnly
# → BPFSocketLBHostnsOnly : Enabled
```

## 落とし穴

### Cilium の設定変更後は、エージェントの再起動が必要

`helm upgrade` で ConfigMap(`bpf-lb-sock-hostns-only = true`)が更新されても、**エージェントは古い設定のまま動き続けた**(実行時は `Disabled`、起動ログも `--bpf-lb-sock-hostns-only='false'`)。
ConfigMap の値ではなく、必ず `cilium-dbg config -a` の実行時の値で確認すること。

この原因が分かるまで、「設定は正しいのに通らない」という状態で、複数の的外れな調査をした(下記)。

### 的外れだった調査

- `socketLB.enabled=false`: 効果なし(もともと `bpf-lb-sock = false`)。戻した。
- ノードの位置(バックエンドが同じノードか別ノードか)や namespace は無関係だった。

### 原因の切り分けに使った方法

`talosctl pcap` で、同じ通信の runc と gVisor の Pod の veth(lxc)をキャプチャして比べた。

- runc の Pod: veth に出た時点で宛先がバックエンドの Pod(`10.244.x.x:8080`)に変換済み(Pod の中の socket-LB による)。
- gVisor の Pod: 宛先が Service の IP(`10.x.x.x:80`)のまま出て、SYN が再送され続けた。

→ 「Pod の中で変換されている」ことから、Pod の中で socket-LB が動いていると分かり、設定が実行時に効いていないことに気づいた。

## 検証結果

### 通信(runc と gVisor を同じ条件で比較)

エージェント再起動後。

| 通信 | runc | gVisor |
|---|---|---|
| Pod IP へ直接 | 通る | 通る |
| ClusterIP(Service の IP) | 通る | 通る |
| Service の短縮名 | 通る | 通る |
| `*.svc.cluster.local` | 通る | 通る |
| `kubernetes.default.svc.cluster.local` の名前解決 | 通る | 通る |

再起動前は、gVisor の ClusterIP / Service 名 / DNS(ClusterIP 経由)がすべて通らなかった。
ホスト側の通信(ノードから Harbor の ClusterIP への pull)にも影響なし。

### ボリューム(Longhorn)

| ボリューム | gVisor |
|---|---|
| RWO | 読み書きできる |
| RWX(NFS) | 読み書きできる |

### 参考: Pod の user namespace(`hostUsers: false`)

| 条件 | 結果 |
|---|---|
| ボリュームなし | 動く。コンテナ内の root は、ホストでは一般ユーザー(uid `1064960000`)に割り当てられる |
| RWO のボリューム | 動く |
| RWX のボリューム | **失敗**(`failed to set MOUNT_ATTR_IDMAP ... filesystem doesn't support idmap mounts`。NFS が idmap マウントに非対応) |

ボリュームを使うアプリには user namespace を付けられない(controller は常に RWX で作る)。gVisor は RWX でも動くので、隔離には gVisor のほうが適している。

### ビルド(rootless buildkit + railpack)を gVisor で動かす

ビルド Job と同じ構成(init コンテナ 3 つ + `buildctl`)を、gVisor の Pod で再現した。

- そのままだと、`RUN` ステップが `exec: "/bin/sh": no such file or directory` で失敗する。gVisor の中では overlay のスナップショッターが使えないため。
- **`BUILDKITD_FLAGS` に `--oci-worker-snapshotter=native` を足すと動く**。
  ```
  BUILDKITD_FLAGS="--oci-worker-no-process-sandbox --oci-worker-snapshotter=native"
  ```
- `sample-go-app` で、証明書の準備、Git クローン、`railpack prepare`、railpack フロントエンドでのビルド、Harbor への push まで成功した(約 2 分)。
- `native` はコピー方式なので、overlay よりビルドは遅く、ディスクも使う。大きなアプリでの影響は未測定。

## 反映が必要な backend の改修(未実施)

gVisor は導入済みだが、アプリは `runtimeClassName` を設定していないため、**まだ gVisor では動いていない**。

- `builder`: ビルド Pod に `runtimeClassName: gvisor` と、上記の `BUILDKITD_FLAGS` を足す。
- `controller`: ユーザーのアプリの Deployment に `runtimeClassName: gvisor` を足す。
