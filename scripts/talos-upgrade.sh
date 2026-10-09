#!/bin/bash
# Talos ノードを新しいインストーラ(拡張入りイメージ)へ更新し、結果を「稼働中のスキーマティック」で検証する。
# 学校 LAN に届く iot-pve1 上で、talosctl / kubectl / TALOSCONFIG / KUBECONFIG を使える状態で実行する。
#
#   scripts/talos-upgrade.sh <ノードIP> <インストーラ画像>
#   例: scripts/talos-upgrade.sh 192.168.10.162 factory.talos.dev/installer/<schematic-id>:v1.13.2
#
# 注意:
#  - 既存ノードに worker-extensions.yaml を丸ごと `talosctl patch mc` で重ねないこと。machine.files / kubelet.extraMounts の
#    リストが二重になり、`EtcFileSpecs ... already exists` でブートが止まる。画像だけ変える場合は install.image のみのパッチを使う。
#  - `talosctl upgrade` の「成功らしい出力」を信用しない。稼働中のスキーマティック(get extensions)で必ず検証する。
set -u
IP=${1:?ノード IP を指定する}; IMG=${2:?インストーラ画像を指定する}
ENDPOINT=${TALOS_ENDPOINT:-192.168.10.161}
WANT=$(echo "$IMG" | sed -E 's#.*/installer/([0-9a-f]+):.*#\1#')
cur() { talosctl -n "$IP" -e "$ENDPOINT" get extensions 2>&1 | grep -v WARNING | awk '$(NF-1)=="schematic"{print $NF}'; }

echo "目標: ${WANT:0:12}… / 現在: $(cur | cut -c1-12)…"
talosctl -n "$IP" -e "$ENDPOINT" upgrade --image "$IMG" --preserve --wait --timeout 12m 2>&1 | grep -v WARNING | tail -12

for _ in $(seq 1 30); do [ "$(cur)" = "$WANT" ] && break; sleep 6; done
if [ "$(cur)" = "$WANT" ]; then
  echo "検証 OK: 稼働中のスキーマティックが目標と一致"
else
  echo "検証 NG: 稼働中=$(cur | cut -c1-12)… / 目標=${WANT:0:12}…" >&2; exit 1
fi

# 設定上の install.image も揃える(次回の更新・再インストールで旧イメージが使われないように)
printf 'machine:\n  install:\n    image: %s\n' "$IMG" > /tmp/img-only.yaml
talosctl -n "$IP" -e "$ENDPOINT" patch mc -p @/tmp/img-only.yaml --mode no-reboot 2>&1 | grep -v WARNING | tail -1
rm -f /tmp/img-only.yaml
