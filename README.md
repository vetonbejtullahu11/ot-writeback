# ot-writeback

End-to-end starter for an RPA-friendly **Logic Apps + SQL write-back + Power BI** solution.

## Goals
1. Clear repo conventions (`infra/`, `app/`, `bi/`, `ops/`)
2. One-command **dev** environment provisioning (Azure RG + Key Vault) via Terraform
3. Guidance to deploy Logic Apps and promote Power BI content

---

## Repository Layout

> Note: Git ignores empty folders. To keep structure visible, add `.gitkeep` files inside empty dirs.

---

## Prerequisites

- **Azure Subscription** + permissions to create RG & Key Vault
- **CLI tools**  
  - [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) → `az --version`  
  - [Terraform >= 1.6](https://developer.hashicorp.com/terraform/downloads) → `terraform -version`
  - **macOS/Linux**: `make` (preinstalled on mac)  
  - **Windows (optional)**: PowerShell 7+

- **IDs you need**  
  - `subscription_id`  
  - `tenant_id`

---

## Quick Start (Dev) — One Command

1. Open `infra/env/dev/dev.tfvars` and set:
   ```hcl
   subscription_id = "<YOUR_SUBSCRIPTION_ID>"
   tenant_id       = "<YOUR_TENANT_ID>"
   location        = "westeurope"
   project_name    = "ot-writeback"
   env             = "dev"
```