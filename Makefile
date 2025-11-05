ENV ?= dev
TF ?= terraform

.PHONY: dev
dev:
	@$(MAKE) -f scripts/Makefile dev \
		TF=$(TF) \
		INFRA_DIR=infra \
		ENV=$(ENV)
