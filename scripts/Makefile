TF=terraform
INFRA_DIR=../infra
ENV=dev
TFVARS=$(INFRA_DIR)/env/$(ENV)/$(ENV).tfvars

.PHONY: dev
dev:
	@echo "🔐 Azure login (only if needed)..."
	-az account show >/dev/null 2>&1 || az login >/dev/null

	cd $(INFRA_DIR) && \
	$(TF) init -reconfigure -upgrade >/dev/null && \
	$(TF) plan -var-file=$(TFVARS) -out=.tfplan && \
	$(TF) apply -auto-approve .tfplan && \
	echo "✅ Dev base infra deployed."
