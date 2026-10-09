# Talos Linux k8s クラスタ(学校 Proxmox: iot-pve1 / iot-pve2)

launchs-org のバックエンドを動かす k8s クラスタの構成と、構築手順の記録です。
秘密情報(トークン、パスワード、鍵)はこのリポジトリに含めません。

## 構成

| 項目 | 内容 |
|---|---|
| ホスト | Proxmox クラスタ `iot-cluster`(iot-pve1 / iot-pve2)。iot-pve3 は QDevice とバックアップ用なので VM は載せない |
| OS | Talos Linux v1.13.2 |
| Kubernetes | 1.36.3(Talos 1.13 は 1.37 に未対応のため固定) |
| ノード | master 1 + worker 4(下表) |
| ストレージ | Longhorn(拡張・RWX 対応)。`local-path` もデフォルトとして残す |
| CNI | Cilium 1.20.2(kube-proxy 置き換え、WireGuard 暗号化) |
| Ingress | Traefik(ClusterIP)。外部公開は Cloudflare Tunnel |
| レジストリ | Harbor(`main-harbor` namespace、`harbor.main-harbor`) |

| VM | ID | ホスト | IP | コア / RAM / ディスク |
|---|---|---|---|---|
| talos-master | 200 | iot-pve1 | 192.168.10.161 | 2 / 4GB / 32GB |
| talos-worker-1 | 201 | iot-pve1 | 192.168.10.162 | 4 / 10GB / 100GB |
| talos-worker-2 | 202 | iot-pve1 | 192.168.10.163 | 4 / 10GB / 100GB |
| talos-worker-3 | 203 | iot-pve2 | 192.168.10.164 | 4 / 12GB / 100GB |
| talos-worker-4 | 204 | iot-pve2 | 192.168.10.165 | 4 / 12GB / 100GB |

VM は Proxmox の HA・複製には登録しません(k8s 側で冗長化するため)。夜間バックアップは全ゲスト対象なので自動で入ります。

## 構築の流れ

1. **VM の作成**(`scripts/mkvm.sh`): Proxmox の API トークンを作らず、root の SSH で `qm` から作成する。ストレージは `zfs-tank`、ISO は `talos-linux1132.iso`。
2. **Talos の設定と bootstrap**(`talos/*.tf`): `siderolabs/talos` プロバイダで、設定生成・適用・bootstrap・kubeconfig 取得まで行う。
   - 初回はメンテナンスモード(DHCP)の IP に適用する(`variables.tf` の `dhcp_ip`)。適用後は固定 IP に切り替わる。
   - 構築後に再適用するときは、`main.tf` の `talos_machine_configuration_apply` の `node` / `endpoint` を `each.value.ip` に切り替える。
3. **Cilium** を Helm で導入する(詳細は [gvisor-cilium.md](gvisor-cilium.md))。
4. **基盤**: Traefik、postgres-operator、Longhorn、Harbor を Helm で導入する。
5. **アプリ**: `manifest` リポジトリの `renew-version` ブランチを、Secret を生成して適用する。Temporal は別途 Helm で入れる。

`terraform` コマンドは学校 LAN に届く iot-pve1 上で実行する。state と talosconfig / kubeconfig はそこにだけ置く(リポジトリには含めない)。

## Talos の設定

| ファイル | 内容 |
|---|---|
| `talos/main.tf` | 全体の定義。CNI なし・kube-proxy 無効・システムディスク暗号化(LUKS2)を共通で入れる |
| `talos/firewall.yaml` | Talos の ingress ファイアウォール。既定でブロックし、必要な通信だけ許可する |
| `talos/userns.yaml` | `user.max_user_namespaces`(rootless buildkit 用。Talos の既定は 0) |
| `talos/worker-extensions.yaml` | worker 用: 拡張入りインストーラ(Longhorn / gVisor / qemu-guest-agent)、Longhorn のマウント、gVisor の登録 |
| `talos/controlplane-extensions.yaml` | master 用: qemu-guest-agent だけを含むインストーラ |
| `talos/harbor-registry.yaml` | ノードから Harbor を引くための hosts と CA の信頼 |

### Talos 1.13 での注意

- ホスト名は `machine.network.hostname` ではなく `HostnameConfig` ドキュメントで指定する(併用すると `static hostname is already set` で拒否される)。
- `machine.files` を変える設定は再起動が必要。`--mode staged` で入れて `talosctl upgrade` の再起動で反映する。

### ファイアウォール

ingress を既定でブロックし、次だけ許可する。変更時は `talosctl patch mc --mode try`(自動ロールバック付き)で適用し、疎通を確認してから本適用する。

| ポート | 許可元 |
|---|---|
| apid 50000 | 管理元(iot-pve1 / iot-pve2)とクラスタのノード |
| trustd 50001、kubelet 10250 | クラスタのノード |
| kube-apiserver 6443 | 管理元、ノード、Pod ネットワーク |
| etcd 2379-2380 | master のみ |
| Cilium(4240/4244/4245 TCP、8472/51871 UDP) | クラスタのノード |
| ICMP | 学校 LAN |

## ノードの更新(拡張入りイメージへの入れ替え)

拡張(Longhorn / gVisor / qemu-guest-agent)を含むイメージへの更新など、再起動を伴う変更は **1 台ずつ** 行う。
worker は drain してから、master は最後に行う(master は 1 台なので、再起動中は数分間 k8s の API が止まる。動いている Pod は影響を受けない)。

### 手順

```bash
# 1. 作業の前に、クラスタが健全であることを確認する(全 Pod が Running、PostgreSQL が 3 台揃っている)
# 2. worker は drain する
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=180s
# 3. 更新して、稼働中のスキーマティックで検証する(scripts/talos-upgrade.sh が検証と install.image の整合までを行う)
scripts/talos-upgrade.sh <ノード IP> factory.talos.dev/installer/<schematic-id>:v1.13.2
kubectl uncordon <node>
# 4. 次のノードへ進む前に、全 Pod が Running で、PostgreSQL が 3 台揃っていることを確認する
```

PostgreSQL の master が載っているノードを更新すると、Patroni のフェイルオーバーが起きる(検証で確認済み)。
worker に固定された `local-path` のボリュームを使う Pod(Harbor の DB など)は、そのノードの更新中は Pending になる(ノードが戻れば復帰する。異常ではない)。

### 守ること(今回の失敗から)

1. **既存ノードに `worker-extensions.yaml` を丸ごと `talosctl patch mc` しない**。`machine.files` と `kubelet.extraMounts` のリストが二重になり、`EtcFileSpecs ... already exists` でブートが止まる(kubelet が起動せず、ノードが NotReady のまま)。
   画像だけ変えるなら `install.image` のみのパッチを使う(`scripts/talos-upgrade.sh` がそうしている)。
   二重になってしまった場合は、`EDITOR` に重複ブロックを取り除くスクリプトを指定して `talosctl edit mc` で直せる(JSON パッチは、マルチドキュメントの設定には使えない)。
2. **`talosctl upgrade` の「成功らしい出力」を信用しない**。ブート失敗でロールバックしても、それらしい出力で終わることがある。必ず `talosctl get extensions` の `schematic` で、稼働中のイメージを検証する。
3. **作業は 1 つのセッションだけで行う**。複数の端末・セッションが同じノードを同時に操作すると、drain や VM の停止・起動が二重に走る。

### qemu-guest-agent(Proxmox から VM の IP などを見る)

Talos の拡張 `siderolabs/qemu-guest-agent` を、イメージに含める(worker は `worker-extensions.yaml`、master は `controlplane-extensions.yaml`)。
さらに、Proxmox の VM に **ゲストエージェントのデバイスを追加する**必要がある。

```bash
qm set <vmid> --agent enabled=1      # 設定を変える。デバイスは VM を起動し直すまで追加されない
```

- `talosctl upgrade` が再起動するのは **ゲスト OS だけ**で、QEMU のプロセス(VM そのもの)は起動し直されない。
  そのため、拡張を入れただけでは Proxmox からエージェントは見えない。**VM を一度停止して起動し直す**(`qm shutdown` → `qm start`)。
- 先に `qm set --agent enabled=1` を入れてから `talosctl upgrade` と VM の停止・起動を行えば、エージェントの応答まで確認できる(`qm agent <vmid> ping`)。
- 起動直後は、DHCP の一時的な IP が一瞬表示されることがある。固定 IP に落ち着くのを待ってから判断する。

## Longhorn

- 前提: Talos 拡張 `iscsi-tools` と `util-linux-tools`、kubelet の `extraMounts`(`/var/lib/longhorn`、`rshared`)。
- `longhorn-system` namespace は PodSecurity を `privileged` にする。
- Helm の値: `persistence.defaultClass=false`(`local-path` をデフォルトのまま残す)、レプリカ数 2。
- `backend` の controller はユーザーのボリュームを `storageClassName: longhorn`、RWX で作るため、Longhorn が必須。
- 検証: RWX のボリュームを 1Gi から 3Gi にオンラインで拡張でき、Pod 内の `df` にも反映された。

## Harbor

- `main-harbor` namespace に、リリース名 `harbor` で導入する(Service 名が `harbor` になり、`harbor.main-harbor` で解決できる)。
- ノードの containerd はクラスタ DNS を使えないため、`talos/harbor-registry.yaml` で次を設定する。
  - `harbor.main-harbor` を Harbor の ClusterIP に固定する hosts エントリ。
  - Harbor の自己署名 CA の信頼(**証明書の検証は無効にしない**)。
- ノードから Harbor への通信は、`talos/manifests/harbor-cnp.yaml`(CiliumNetworkPolicy)で、nginx の 8443/8080 だけ許可する。`manifest` の `harbor-combined-policy` は旧環境のノード網(`10.10.11.0/24`)しか許可していない。
- Harbor の証明書の期限は発行から 1 年。期限が切れると、ノードの CA 信頼とアプリからの接続が壊れるので、更新時は CA の再取得と Talos の設定の更新が必要。
- アプリには admin ではなく、専用のロボットアカウント(システムレベルでプロジェクト作成、全プロジェクトに対して controller と同じ権限)を使う。

## アプリ(`manifest` の `renew-version`)の差分

- `longhorn` の RWX は、そのまま使う。
- イメージはダイジェストで固定する。
- watcher の ClusterRole に `persistentvolumeclaims` と `ingressroutes` の読み取り権限を足す(upstream の `rbac.yaml` に不足)。
- postgres-operator は `postgres-operator` namespace にいるので、DB への管理接続を許可する NetworkPolicy を足す。
- 全 Deployment に `seccompProfile: RuntimeDefault`、`allowPrivilegeEscalation: false`、`capabilities.drop: [ALL]` を足す(`runAsNonRoot` は root 前提のイメージを壊すため付けない)。

## プロジェクト namespace の egress 制限

controller は新しいプロジェクトの namespace に、egress を全許可する NetworkPolicy を作る。
`talos/manifests/egress-policy.yaml` は、egress を次に限定した置き換え用のポリシー。

- 同じ namespace の Pod
- DNS(kube-system の kube-dns)
- インターネット(プライベート帯 `10/8`、`172.16/12`、`192.168/16`、`100.64/10`、`169.254/16` を除く)

検証結果(プロジェクト namespace 内のテスト Pod から):

| 宛先 | 結果 |
|---|---|
| クラスタ内の DNS、同じ namespace の Pod、インターネット | 通る |
| 同じ namespace の Service 名(`*.svc.cluster.local`) | 通る |
| k8s API サーバー、ノード、Proxmox、他 namespace(Harbor、Temporal 等) | 遮断 |

backend 側の恒久対応(controller のコード)は `backend` リポジトリのブランチ `feat/egress-restrict-project-ns`。

## Cloudflare Tunnel

`talos/manifests/cloudflared.yaml` の Deployment を使う(トークンは含まない)。

```bash
kubectl -n cloudflared create secret generic cloudflared-token --from-file=token=/dev/stdin   # 標準入力でトークンを渡す
kubectl apply -f talos/manifests/cloudflared.yaml
```

Public Hostname の向け先は `http://traefik.traefik.svc.cluster.local:80`。`*.launchs.org` も同じ向けにする(アプリの Ingress が動的に作られるため)。
