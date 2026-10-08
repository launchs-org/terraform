#!/bin/bash
# usage: mkvm.sh <vmid> <name> <cores> <mem_mb> <disk_gb>  (Proxmox ノード上で root として実行)
set -euo pipefail
id=$1 name=$2 cores=$3 mem=$4 disk=$5
qm create $id --name $name --description "Talos k8s (launchs-org)" --tags talos,k8s \
  --bios ovmf --machine q35 --ostype l26 --cpu host --cores $cores \
  --memory $mem --balloon 0 --scsihw virtio-scsi-pci \
  --efidisk0 zfs-tank:1,efitype=4m,pre-enrolled-keys=0 \
  --scsi0 zfs-tank:$disk,discard=on,ssd=1 \
  --ide2 local:iso/talos-linux1132.iso,media=cdrom \
  --net0 virtio,bridge=vmbr0,macaddr=BC:24:11:A0:00:$(printf %02X $((id-200))) \
  --boot "order=scsi0;ide2" --onboot 1 --agent 0
echo "created $id $name"
