resource "proxmox_virtual_environment_vm" "virtual_machines" {
  for_each = var.vms

  name        = each.value.name
  node_name   = each.value.node_name
  vm_id       = each.value.vm_id
  description = "Managed by Terraform"
  tags        = ["terraform", "talos"]

  # Stop on deletion if agent is not there
  stop_on_destroy = false

  bios    = "ovmf"
  machine = "q35"
  scsi_hardware = "virtio-scsi-pci"

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = 0 # Disable ballooning as Talos doesn't support memory hotplug
  }

  # Disk configuration
  disk {
    datastore_id = each.value.datastore_id
    interface    = "scsi0"
    iothread     = false
    size         = each.value.disk_size
    file_format  = "raw"
  }

  # EFI Disk (Required for OVMF)
  efi_disk {
    datastore_id = each.value.datastore_id
    file_format  = "raw"
    type         = "4m"
  }

  # CD-ROM configuration (ISO image)
  cdrom {
    file_id   = each.value.image_id
    interface = "ide2"
  }

  # Network Adapter
  network_device {
    bridge = each.value.network_bridge
    model  = "virtio"
    mtu    = each.value.mtu
  }

  operating_system {
    type = "l26"
  }

  # Cloud-Init device for passing network config or using NoCloud datasource
  initialization {
    datastore_id = each.value.datastore_id
    interface    = "ide3"
    dns {
      servers = each.value.dns_servers
      domain  = each.value.dns_domain
    }
    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.gateway
      }
    }
  }
}
