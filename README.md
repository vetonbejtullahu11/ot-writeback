# ot-writeback

End-to-end starter for an RPA-friendly **Logic Apps + SQL write-back + Power BI** solution.

## Goals
1. Clear repo conventions (`infra/`, `app/`, `bi/`, `ops/`)
2. One-command **dev** environment provisioning (Azure RG + Key Vault) via Terraform
3. Guidance to deploy Logic Apps and promote Power BI content

---

## Repository Layout

> Note: Git ignores empty folders. To keep structure visible, add `.gitkeep` files inside empty dirs.

- `infra/` — Terraform root (`main.tf`) plus reusable modules under `infra/modules/*`
- `infra/env/<env>/` — per-environment variable files (`dev`, `test`, `prod`)
- `scripts/` — automation helpers; `Makefile` target drives Terraform workflow
- `app/` — application code placeholder (Logic App artifacts, Functions, etc.)
- `bi/` — Power BI assets (PBIX files, deployment pipelines)
- `ops/` — runbooks, operational docs, incident playbooks
- `ot_demo/` — sample SQL artifacts used in workshops/demos

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

1. Edit `infra/env/dev/dev.tfvars` and set the Azure subscription + tenant IDs along with any subnet values you need:
   ```hcl
   subscription_id = "<YOUR_SUBSCRIPTION_ID>"
   tenant_id       = "<YOUR_TENANT_ID>"
   location        = "westeurope"
   project_name    = "ot-writeback"
   env             = "dev"

   vnet_address_space = ["10.10.0.0/16"]
   apps_subnet_prefix = "10.10.1.0/24"
   data_subnet_prefix = "10.10.2.0/24"

   admin_password = "<STRONG_SQL_PASSWORD>"
   ```
2. Authenticate with Azure CLI if needed: `az login`.
3. Provision the environment from the repo root: `make dev`.  
   - Under the covers this runs `terraform init`, `plan`, and `apply` via `scripts/Makefile`.
   - Override the target environment with `ENV=test make dev`, etc.
4. Inspect the outputs (SQL FQDN, Key Vault URI, Logic App MI) in the terminal or via `terraform output`.

## Infrastructure Modules

- **networking** — VNet, app/data subnets, and optional SQL private DNS zone + link
- **sql** — Azure SQL server/database, Transparent Data Encryption, private endpoint
- **logicapp** — Logic App Standard with system-assigned managed identity
- **monitor** — Log Analytics workspace + Application Insights
- **keyvault** — Central Key Vault with purge protection enabled

## Deploying the Logic App (Standard)

1. Package your workflow code in `app/` (for example via `func azure functionapp publish` or `az logicapp`). Logic Apps Standard expects a zipped artifact with `host.json` and workflows.
2. Create/update the workflow using the managed identity that Terraform provisioned (`terraform output mi_principal_id`).
3. For simple edits, use the Workflow Designer in the Azure Portal; for CI/CD, push a zip to the Logic App’s `scm` endpoint:
   ```bash
   az webapp deployment source config-zip \
     --resource-group <rg> \
     --name <logic-app-name> \
     --src ./app/workflows.zip
   ```
4. Store any secrets (SQL connection strings, API keys) in Key Vault and reference them from the workflow using managed identity.

## Promoting Power BI Content

1. Author reports in Power BI Desktop and save `.pbix` files under `bi/`.
2. Publish to the dev workspace using the Power BI Service or `pbip` CLI.
3. Use deployment pipelines (Dev → Test → Prod) to promote content; document approvals in `ops/` as runbooks.
4. Parameterize data sources so the promoted workspace picks up the correct SQL endpoint (from Terraform outputs).

---

## Terraform Details

### State backend
This starter uses **local state**. For teams, switch to remote state (Storage Account) later and enable a `backend "azurerm"` block per env.

### Useful commands
```bash
cd infra
terraform fmt -recursive
terraform validate
# (later) terraform init -reconfigure
# (later) terraform plan -var-file=env/dev/dev.tfvars -out=.tfplan
