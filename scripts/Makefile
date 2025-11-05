TF ?= terraform
INFRA_DIR ?= ../infra
ENV ?= dev
TFVARS ?= env/$(ENV)/$(ENV).tfvars

.PHONY: dev
dev:
	@echo "🔐 Azure login (only if needed)..."
	-az account show >/dev/null 2>&1 || az login >/dev/null
	$(TF) -chdir=$(INFRA_DIR) init -reconfigure -upgrade >/dev/null
	$(TF) -chdir=$(INFRA_DIR) plan -var-file=$(TFVARS) -out=.tfplan
	$(TF) -chdir=$(INFRA_DIR) apply -auto-approve .tfplan
	@echo "✅ Dev base infra deployed."
