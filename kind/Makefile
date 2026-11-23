# lab-ai-guardrails-n8n/kind — local kind cluster for the lab (default inside the devcontainer: CLUSTER=kind).
# Works anywhere `docker` + `kind` exist: the devcontainer (Docker-in-Docker), Codespaces, or a plain host.
# Run `make` for the target list.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

ROOT_DIR     := $(abspath ..)
KIND_CLUSTER ?= mk8s-lab
KUBECONFIG_FILE := $(ROOT_DIR)/.state/kind.kubeconfig
NODE         := $(KIND_CLUSTER)-control-plane

.PHONY: help up down info k9s

help: ## Show targets
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-6s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

up: ## Create the kind cluster (or start it again after a container restart); idempotent
	@command -v kind >/dev/null && command -v docker >/dev/null || { echo "kind and docker are required (use the devcontainer)"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo -n "Waiting for the Docker daemon"; for i in $$(seq 60); do docker info >/dev/null 2>&1 && break; echo -n .; sleep 2; done; echo; }
	@if kind get clusters 2>/dev/null | grep -qx '$(KIND_CLUSTER)'; then \
	   if [ "$$(docker inspect -f '{{.State.Running}}' $(NODE) 2>/dev/null)" != true ]; then echo "Starting kind node $(NODE)..."; docker start $(NODE) >/dev/null; fi; \
	 else \
	   kind create cluster --name $(KIND_CLUSTER) --config kind-config.yaml --wait 180s; \
	 fi
	@mkdir -p $(dir $(KUBECONFIG_FILE)) && chmod 700 $(dir $(KUBECONFIG_FILE))
	@(umask 077; kind get kubeconfig --name $(KIND_CLUSTER) > $(KUBECONFIG_FILE))
	@KUBECONFIG=$(KUBECONFIG_FILE) kubectl wait node --all --for=condition=Ready --timeout=180s >/dev/null
	@$(MAKE) --no-print-directory info

down: ## Delete the kind cluster and everything in it
	@kind delete cluster --name $(KIND_CLUSTER)
	@rm -f $(KUBECONFIG_FILE)

info: ## Cluster, node, versions, apps
	@kind get clusters 2>/dev/null | grep -qx '$(KIND_CLUSTER)' || { echo "No kind cluster '$(KIND_CLUSTER)'. Run 'make up'."; exit 1; }
	@export KUBECONFIG=$(KUBECONFIG_FILE); \
	 printf "  %-11s %s\n" Cluster "kind/$(KIND_CLUSTER)  (kubeconfig .state/kind.kubeconfig)" \
	   Node "$$(kubectl get node -o jsonpath='{.items[0].metadata.name} {.items[0].status.nodeInfo.kubeletVersion} {.items[0].status.nodeInfo.architecture}')" \
	   Releases "$$(helm list -A -q 2>/dev/null | tr '\n' ' ')"; \
	 echo "  Next: make -C n8n up && make -C llmgw secrets && make -C llmgw up   (CLUSTER=$${CLUSTER:-kind})"

k9s: ## Open k9s on the kind cluster
	@KUBECONFIG=$(KUBECONFIG_FILE) k9s
