resource "proxmox_virtual_environment_vm" "virtual_machines" {
  for_each = var.vms

  name        = each.value.name
  node_name   = each.value.node_name
  vm_id       = each.value.vm_id
  description = "Managed by Terraform"
  tags        = ["terraform"]

  # Stop on deletion if agent is not there
  stop_on_destroy = false

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # Disk configuration (Empty disk for OS installation)
  disk {
    datastore_id = each.value.datastore_id
    interface    = "virtio0"
    iothread     = true
    size         = each.value.disk_size
  }

  # CD-ROM configuration (ISO image)
  cdrom {
    file_id   = each.value.image_id
    interface = "ide2"
  }

  # Network Adapter
  network_device {
    bridge = each.value.network_bridge
  }

  # Cloud-Init / IP configuration
  initialization {
    datastore_id = each.value.datastore_id
    interface    = "ide3"
    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.gateway
      }
    }
  }
}
