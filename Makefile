# lab-ai-guardrails-n8n — top-level entry point for the devcontainer lab (kind).
# Run `make` for the target list. See LAB-DEVCONTAINER-LOCAL.md and LAB-CODESPACES.md.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

KUBECONFIG_KIND := $(CURDIR)/.state/kind.kubeconfig
TUNNEL_BG       := $(CURDIR)/n8n/scripts/tunnel-bg.sh

.PHONY: help check-devcontainer up n8n-passwd n8n-tunnel n8n-tunnel-status n8n-tunnel-logs n8n-tunnel-stop down

help: ## Show targets
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-18s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

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
	@echo "==> [5/5] Starting the n8n tunnel (background tmux session)..."
	@$(TUNNEL_BG) start || echo "  Tunnel not started. Foreground fallback, in a second terminal: make -C n8n tunnel"
	@echo
	@echo "==> Lab is ready! Open n8n in your browser:"
	@if [ -n "$${CODESPACE_NAME:-}" ]; then \
	   echo "  URL       https://$${CODESPACE_NAME}-8443.$${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}/"; \
	   echo "            (or the Ports tab globe icon on \"n8n\"; GitHub's own cert, no CA step; keep the port Private)"; \
	 else \
	   echo "  URL       https://n8n.localhost:8443/   (VS Code forwards port 8443 to the Mac)"; \
	   echo "  Trust CA  once per lab build, on the Mac (each cluster has its own CA):"; \
	   echo "              sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \\"; \
	   echo "                ~/github/lab-ai-guardrails-n8n/n8n/.state/kind/ca.crt   (adjust if cloned elsewhere)"; \
	 fi
	@$(MAKE) --no-print-directory n8n-passwd
	@echo
	@echo "  Tunnel: make n8n-tunnel-status | n8n-tunnel-logs | n8n-tunnel-stop   (it restarts itself when n8n restarts)"
	@echo "  Demo:   Workflows -> \"llmgw chat agent (Lakera-guarded)\" -> Open chat."

n8n-passwd: ## Show the pre-created n8n owner email and generated password
	@$(MAKE) --no-print-directory -C n8n passwd

n8n-tunnel: ## n8n on 127.0.0.1:8443 in a background tmux session (auto-restarts; rerun restarts it if unhealthy)
	@$(TUNNEL_BG) start

n8n-tunnel-status: ## Background n8n tunnel: tmux session, port, HTTPS health
	@$(TUNNEL_BG) status

n8n-tunnel-logs: ## Background n8n tunnel log (TAIL=50; FOLLOW=1 follows)
	@$(TUNNEL_BG) logs

n8n-tunnel-stop: ## Stop the background n8n tunnel
	@$(TUNNEL_BG) stop

down: ## Stop n8n and llmgw (PURGE=1 also deletes data and stored keys; kind cluster stays up)
	@$(MAKE) --no-print-directory -C n8n down PURGE=$(PURGE)
	@$(MAKE) --no-print-directory -C llmgw down PURGE=$(PURGE)
