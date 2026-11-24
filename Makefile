# lab-ai-guardrails-n8n — top-level entry point for the devcontainer lab (kind).
# Run `make` for the target list. See LAB-DEVCONTAINER-LOCAL.md and LAB-CODESPACES.md.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

KUBECONFIG_KIND := $(CURDIR)/.state/kind.kubeconfig

.PHONY: help check-devcontainer up n8n-passwd n8n-tunnel down

help: ## Show targets
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-12s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

check-devcontainer:
	@if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ -z "$${REMOTE_CONTAINERS:-}$${CODESPACES:-}$${DEVCONTAINER:-}" ]; then \
	   echo "ERROR: 'make up' must run inside the devcontainer (kind), not on the host."; \
	   echo "  VS Code:  ⇧⌘P -> Dev Containers: Reopen in Container"; \
	   echo "  Guides:   LAB-DEVCONTAINER-LOCAL.md (devcontainer), LAB-GUIDE.md (Docker Desktop), vm/README.md (Azure VM)"; \
	   exit 1; \
	 fi
	@if [ "$${CLUSTER:-}" != "kind" ]; then \
	   echo "ERROR: expected CLUSTER=kind (preset by this repo's devcontainer), got '$${CLUSTER:-unset}'."; \
	   echo "  Make sure you are inside the lab-ai-guardrails-n8n devcontainer."; \
	   exit 1; \
	 fi
	@for t in docker kind kubectl helm jq openssl curl; do \
	   command -v "$$t" >/dev/null || { echo "ERROR: required devcontainer tool '$$t' not found."; exit 1; }; \
	 done

up: check-devcontainer ## Bring up the full lab in the devcontainer (kind -> n8n -> llmgw -> connect & test)
	@echo "==> [1/5] Starting kind cluster (mk8s-lab)..."
	@$(MAKE) --no-print-directory -C kind up
	@echo
	@echo "==> [2/5] Deploying and testing n8n..."
	@$(MAKE) --no-print-directory -C n8n up CLUSTER=kind
	@$(MAKE) --no-print-directory -C n8n test CLUSTER=kind
	@echo
	@echo "==> [3/5] Configuring, deploying, and testing LLM gateway (Lakera Guard)..."
	@if KUBECONFIG="$(KUBECONFIG_KIND)" kubectl -n llmgw get secret llmgw-provider-keys >/dev/null 2>&1 && [ -z "$${PROMPT:-}" ]; then \
	   echo "Provider secrets already present in llmgw/llmgw-provider-keys (run 'make -C llmgw secrets' to update)."; \
	 else \
	   $(MAKE) --no-print-directory -C llmgw secrets CLUSTER=kind; \
	 fi
	@$(MAKE) --no-print-directory -C llmgw up CLUSTER=kind
	@$(MAKE) --no-print-directory -C llmgw test CLUSTER=kind
	@echo
	@echo "==> [4/5] Connecting n8n to llmgw and testing end-to-end..."
	@$(MAKE) --no-print-directory -C llmgw client-key CLIENT=n8n CLUSTER=kind
	@$(MAKE) --no-print-directory -C n8n llm-connect CLUSTER=kind
	@$(MAKE) --no-print-directory -C n8n llm-test CLUSTER=kind
	@echo
	@echo "==> [5/5] Lab is ready! How to open n8n in your browser:"
	@owner=$$(KUBECONFIG="$(KUBECONFIG_KIND)" kubectl -n n8n get secret n8n-owner -o jsonpath='{.data.email}' 2>/dev/null | base64 -d || true); \
	 owner=$${owner:-guru@example.com}; \
	 echo; \
	 echo "  1. In a second container terminal (+), start the n8n tunnel and leave it running:"; \
	 echo "       make n8n-tunnel          # (same as: make -C n8n tunnel)"; \
	 echo; \
	 if [ -n "$${CODESPACE_NAME:-}" ]; then \
	   url="https://$${CODESPACE_NAME}-8443.$${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}/"; \
	   echo "  2. Open n8n via the Ports tab globe icon on \"n8n\" (port 8443), or:"; \
	   echo "       $$url"; \
	   echo "     (GitHub terminates TLS with its own cert — no CA trust step needed; keep port Private.)"; \
	   echo; \
	   echo "  3. Sign in with the pre-created owner account:"; \
	 else \
	   echo "  2. On your Mac (once per lab build; each cluster has its own CA), trust the n8n CA:"; \
	   echo "       sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \\"; \
	   echo "         ~/github/lab-ai-guardrails-n8n/n8n/.state/kind/ca.crt"; \
	   echo "     (Adjust the path if you cloned the repo elsewhere. VS Code forwards port 8443 automatically.)"; \
	   echo; \
	   echo "  3. Open in your Mac browser:"; \
	   echo "       https://n8n.localhost:8443/"; \
	   echo; \
	   echo "  4. Sign in with the pre-created owner account:"; \
	 fi; \
	 echo "       Email:     $$owner"; \
	 echo "       Password:  run 'make n8n-passwd'"; \
	 echo; \
	 echo "  Demo: open Workflows -> \"llmgw chat agent (Lakera-guarded)\" -> Open chat."

n8n-passwd: ## Show the pre-created n8n owner email and generated password
	@$(MAKE) --no-print-directory -C n8n passwd

n8n-tunnel: ## Forward n8n HTTPS to 127.0.0.1:8443 (keep open; Ctrl+C ends)
	@$(MAKE) --no-print-directory -C n8n tunnel

down: ## Stop n8n and llmgw (PURGE=1 also deletes data and stored keys; kind cluster stays up)
	@$(MAKE) --no-print-directory -C n8n down PURGE=$(PURGE)
	@$(MAKE) --no-print-directory -C llmgw down PURGE=$(PURGE)
