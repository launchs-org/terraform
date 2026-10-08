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
| `talos/worker-extensions.yaml` | 拡張入りインストーラ、Longhorn のマウント、gVisor の登録 |
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

## ローリング更新(worker)

拡張入りイメージへの更新など、再起動を伴う変更は worker を 1 台ずつ行う。

```bash
IMG=factory.talos.dev/installer/<schematic-id>:v1.13.2
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=180s
talosctl -n <ip> patch mc -p @worker-extensions.yaml --mode staged
talosctl -n <ip> upgrade --image "$IMG" --wait --timeout 8m
kubectl uncordon <node>
# 次のノードへ進む前に、全 Pod が Running で、PostgreSQL が 3 台揃っていることを確認する
```

PostgreSQL の master が載っているノードを更新すると、Patroni のフェイルオーバーが起きる(検証で確認済み)。

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
