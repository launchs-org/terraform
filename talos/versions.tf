terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}
