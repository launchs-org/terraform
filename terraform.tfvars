vms = {
  "talos-master" = {
    name         = "talos-master"
    node_name    = "ubuntu1"
    vm_id        = 200
    cpu_cores    = 5
    memory       = 4096 # 4GB
    datastore_id = "local-lvm"
    disk_size    = 32
    image_id     = "local:iso/talos-linux-1123.iso"
    network_bridge = "evnet1"
    ip_address   = "10.10.11.10/24"
    gateway      = "10.10.11.254"
  }
  "talos-worker-1" = {
    name         = "talos-worker-1"
    node_name    = "ubuntu1"
    vm_id        = 201
    cpu_cores    = 5
    memory       = 12288 # 12GB
    datastore_id = "local-lvm"
    disk_size    = 120
    image_id     = "local:iso/talos-linux-1123.iso"
    network_bridge = "evnet1"
    ip_address   = "10.10.11.11/24"
    gateway      = "10.10.11.254"
  }
  "talos-worker-2" = {
    name         = "talos-worker-2"
    node_name    = "ubuntu1"
    vm_id        = 202
    cpu_cores    = 5
    memory       = 12288 # 12GB
    datastore_id = "local-lvm"
    disk_size    = 120
    image_id     = "local:iso/talos-linux-1123.iso"
    network_bridge = "evnet1"
    ip_address   = "10.10.11.12/24"
    gateway      = "10.10.11.254"
  }
  "talos-worker-3" = {
    name         = "talos-worker-3"
    node_name    = "ubuntu2"
    vm_id        = 203
    cpu_cores    = 5
    memory       = 14336 # 14GB
    datastore_id = "local-lvm"
    disk_size    = 120
    image_id     = "local:iso/talos-linux-1123.iso"
    network_bridge = "evnet1"
    ip_address   = "10.10.11.13/24"
    gateway      = "10.10.11.254"
  }
  "talos-worker-4" = {
    name         = "talos-worker-4"
    node_name    = "ubuntu2"
    vm_id        = 204
    cpu_cores    = 5
    memory       = 14336 # 14GB
    datastore_id = "local-lvm"
    disk_size    = 120
    image_id     = "local:iso/talos-linux-1123.iso"
    network_bridge = "evnet1"
    ip_address   = "10.10.11.14/24"
    gateway      = "10.10.11.254"
  }
}
