variable "cluster_name" {
  type    = string
  default = "k8s-cluster"
}

variable "talos_version" {
  type        = string
  description = "ISO と同じ Talos のバージョン"
  default     = "v1.13.2"
}

variable "kubernetes_version" {
  type        = string
  description = "Talos 1.13 がサポートする Kubernetes(1.37 は未対応)"
  default     = "1.36.3"
}

variable "gateway" {
  type    = string
  default = "192.168.10.254"
}

variable "prefix_length" {
  type    = number
  default = 24
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

# bootstrap 前のメンテナンスモード(DHCP)の IP と、最終的な固定 IP
variable "controlplane" {
  type = map(object({ dhcp_ip = string, ip = string }))
  default = {
    "talos-master" = { dhcp_ip = "192.168.10.7", ip = "192.168.10.161" }
  }
}

variable "workers" {
  type = map(object({ dhcp_ip = string, ip = string }))
  default = {
    "talos-worker-1" = { dhcp_ip = "192.168.10.6", ip = "192.168.10.162" }
    "talos-worker-2" = { dhcp_ip = "192.168.10.5", ip = "192.168.10.163" }
    "talos-worker-3" = { dhcp_ip = "192.168.10.8", ip = "192.168.10.164" }
    "talos-worker-4" = { dhcp_ip = "192.168.10.9", ip = "192.168.10.165" }
  }
}
