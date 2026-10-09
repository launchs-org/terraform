locals {
  cp_ip         = one([for n in var.controlplane : n.ip])
  cluster_endpt = "https://${local.cp_ip}:6443"
  installer     = "ghcr.io/siderolabs/installer:${var.talos_version}"

  common_patch = {
    cluster = {
      network = { cni = { name = "none" } } # Cilium を後から helm で入れる
      proxy   = { disabled = true }         # Cilium の kube-proxy replacement を使う
    }
    machine = {
      install = { disk = "/dev/sda", image = local.installer, wipe = false }
      systemDiskEncryption = {
        state     = { provider = "luks2", keys = [{ slot = 0, nodeID = {} }] }
        ephemeral = { provider = "luks2", keys = [{ slot = 0, nodeID = {} }] }
      }
    }
  }

  nodes = merge(
    { for k, v in var.controlplane : k => merge(v, { role = "controlplane" }) },
    { for k, v in var.workers : k => merge(v, { role = "worker" }) },
  )
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "this" {
  for_each = local.nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpt
  machine_type     = each.value.role
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode(local.common_patch),
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            deviceSelector = { physical = true }
            addresses      = ["${each.value.ip}/${var.prefix_length}"]
            routes         = [{ network = "0.0.0.0/0", gateway = var.gateway }]
          }]
          nameservers = var.dns_servers
        }
      }
    }),
    each.value.role == "worker" ? file("${path.module}/userns.yaml") : "", # rootless buildkit 用
    each.value.role == "worker" ? file("${path.module}/worker-extensions.yaml") : file("${path.module}/controlplane-extensions.yaml"), # 拡張入りイメージ(worker: Longhorn / gVisor / guest-agent、controlplane: guest-agent)
    each.value.role == "worker" ? file("${path.module}/harbor-registry.yaml") : "", # Harbor の名前解決と CA の信頼
    file("${path.module}/firewall.yaml"), # ingress は既定でブロックし、必要な通信だけ許可
    # Talos 1.12 以降は、ホスト名を v1alpha1 ではなく HostnameConfig で指定する
    <<-EOT
      apiVersion: v1alpha1
      kind: HostnameConfig
      auto: off
      hostname: ${each.key}
    EOT
  ]
}

# 初回は DHCP の IP に適用する。適用後に固定 IP へ切り替わる
resource "talos_machine_configuration_apply" "this" {
  for_each = local.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  # 初回構築のみ dhcp_ip。構築後に再適用するときは each.value.ip に切り替える
  node     = each.value.dhcp_ip
  endpoint = each.value.dhcp_ip
}

resource "time_sleep" "after_apply" {
  depends_on      = [talos_machine_configuration_apply.this]
  create_duration = "120s" # インストール、再起動、固定 IP への切替を待つ
}

resource "talos_machine_bootstrap" "this" {
  depends_on           = [time_sleep.after_apply]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip
  endpoint             = local.cp_ip
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for n in local.nodes : n.ip]
  endpoints            = [local.cp_ip]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip
  endpoint             = local.cp_ip
}

resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.module}/out/talosconfig"
  file_permission = "0600"
}

resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/out/kubeconfig"
  file_permission = "0600"
}
