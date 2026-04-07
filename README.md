# Proxmox VM Automation with Terraform

このプロジェクトは、Terraform を使用して Proxmox 上に複数の仮想マシン（Talos Linux などの Kubernetes ノード用）を自動展開するための構成です。

## 構成の概要

- **Provider**: [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest)
- **主要な機能**:
    - Proxmox 上へのリソース（VM）の一括作成
    - `for_each` を使用した可変個数のノード管理
    - 秘密情報の分離（`*.auto.tfvars` による自動読み込み）
    - Cloud-Init / ネットワーク設定の自動化

## ファイル構成

- `main.tf`: VM リソースの定義
- `variables.tf`: 変数の定義（秘密情報は `sensitive` 設定済み）
- `providers.tf`: Provider の設定
- `terraform.tfvars`: サーバーのスペックやネットワーク構成などの一般設定
- `secret.tfvars.example`: 秘密情報のテンプレート
- `secret.auto.tfvars`: (作成が必要) 実際の秘密情報用ファイル（Git除外対象）

## セットアップ手順

### 1. 依存関係のインストール

Terraform がインストールされていることを確認し、プロジェクトを初期化します。

```bash
terraform init
```

### 2. 秘密情報の構成

`secret.tfvars.example` をコピーして、自分の環境に合わせて `secret.auto.tfvars` を作成します。このファイル名は Terraform によって自動的に読み込まれるため、コマンドライン引数での指定は不要です。

```bash
# Windows (PowerShell) の場合
copy secret.tfvars.example secret.auto.tfvars
```

`secret.auto.tfvars` を編集し、以下の項目を設定してください：

- `proxmox_endpoint`: Proxmox API の URL (例: https://192.168.1.100:8006/)
- `proxmox_api_token`: Proxmox で発行した API トークン
- `proxmox_insecure`: 自己署名証明書を使用している場合は `true`

> [!IMPORTANT]
> `secret.auto.tfvars` は `.gitignore` によって除外されており、秘密情報がリポジトリに公開されるのを防ぎます。

### 3. VM 構成のカスタマイズ

`terraform.tfvars` を編集して、デプロイする VM の数やスペック（CPU, メモリ, ディスク）、IP アドレスなどをネットワーク構成に合わせて調整します。

## 実行コマンド

構成を確認し、適用します。

```bash
# 実行計画の確認
terraform plan

# リソースの作成・更新
terraform apply

# リソースの削除
terraform destroy
```

## セキュリティと運用

- **秘密情報の保護**: API トークンなどの変数は `sensitive = true` に設定されているため、`terraform plan` や `apply` のログに値が直接表示されることはありません。
- **ノード管理**: `vms` マップに変数を追加・削除するだけで、動的に VM の数を調整できます。
