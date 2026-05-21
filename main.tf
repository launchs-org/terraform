terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.75.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.7.1"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.10.105:8006/"
  insecure = true
}


module "talos" {
    source  = "bbtechsys/talos/proxmox"
    version = "0.1.5"
    talos_cluster_name = "k8s-cluster"
    talos_version = "1.9.5"
    control_nodes = {
        "talos-master-0" = "ubuntu1"
    }
    worker_nodes = {
        "talos-worker-0" = "ubuntu1"
        "talos-worker-1" = "ubuntu1"
        "talos-worker-2" = "ubuntu2"
        "talos-worker-3" = "ubuntu2"
    }
}

output "talos_config" {
    description = "Talos configuration file"
    value       = module.talos.talos_config
    sensitive   = true
}

output "kubeconfig" {
    description = "Kubeconfig file"
    value       = module.talos.kubeconfig
    sensitive   = true
}
