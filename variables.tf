variable "proxmox_endpoint" {
  type      = string
  sensitive = true
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "vms" {
  description = "A map of VMs and their configurations"
  type = map(object({
    name         = string
    node_name    = string
    vm_id        = number
    cpu_cores    = number
    memory       = number # in MB
    datastore_id = string
    disk_size    = number # in GB
    image_id     = string # Path to ISO or Cloud Image (e.g. "local:iso/...)
    network_bridge = string
    ip_address   = string # e.g. "192.168.1.10/24"
    gateway      = string
    dns_servers  = list(string)
    dns_domain   = string
  }))
  default = {}
}
