# lab-ai-guardrails-n8n/llmgw — private LiteLLM gateway to OpenRouter free models, guarded by Check Point Lakera Guard.
# Runs on ../vm MicroK8s (CLUSTER=vm, default; via `make tunnel` in ../vm) Docker Desktop (CLUSTER=docker) or kind (CLUSTER=kind, devcontainer). Not exposed outside the cluster; reach it with `make tunnel` here.
# Run `make` for the target list.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

include ../common/k8s.mk

STATE      := $(CURDIR)/.state/$(CLUSTER)
CA_FILE    := $(STATE)/ca.crt
MODELS     := $(STATE)/models.json
NS         ?= llmgw
RELEASE    ?= llmgw
GW_HOST    ?= llmgw.localhost
PORT       ?= 4443
TEST_PORT  ?= 14443
TEST_MODEL ?= openrouter/free
PROVIDER_SECRET := llmgw-provider-keys
HELM_ARGS  ?=
# UNGUARDED=1 also publishes unguarded/<id> models (no guardrail): for side-by-side comparison demos only (no guardrail).
UNGUARDED  ?=

URL     = https://$(GW_HOST):$(PORT)
K       = kubectl -n $(NS)

.PHONY: help secrets up down info test tunnel ca models addons key client-key

help: ## Show targets
	@echo "  Cluster: $(CLUSTER)   (CLUSTER=vm | docker | kind)"; echo
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-8s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

secrets: ## OpenRouter key, Lakera key + project -> Kubernetes Secret (prompts, or Codespaces secrets from env)
	@$(PREFLIGHT)
	@scripts/secrets.sh $(NS) $(PROVIDER_SECRET) $(RELEASE)

models: ## Refresh the free model list from the OpenRouter catalog (.state/models.json)
	@mkdir -p $(STATE)
	@scripts/models.sh > $(MODELS).tmp && mv $(MODELS).tmp $(MODELS)
	@echo "Free text models: $$(jq '.models|length' $(MODELS)) ($$(jq -r '.models|join(", ")' $(MODELS) | cut -c1-140)...)"

addons: ## Ensure cert-manager (MicroK8s addon on vm, Helm chart on docker/kind; part of up)
	@$(PREFLIGHT)
	@$(ENSURE_ADDONS) cert-manager

up: addons models ## Deploy/upgrade LiteLLM + Lakera guardrails, wait until ready, print info
	@$(K) get secret $(PROVIDER_SECRET) >/dev/null 2>&1 || { echo "Provider keys missing. Run first:  make secrets   (in Claude Code:  ! make -C llmgw secrets CLUSTER=$(CLUSTER))"; exit 1; }
	@helm upgrade --install $(RELEASE) chart -n $(NS) --create-namespace -f $(MODELS) \
	  --set host=$(GW_HOST) --set localPort=$(PORT) --set secrets.providers=$(PROVIDER_SECRET) --set variants.unguarded=$(if $(UNGUARDED),true,false) \
	  --wait --timeout 10m $(HELM_ARGS)
	@$(K) wait certificate/$(RELEASE)-tls --for=condition=Ready --timeout=120s >/dev/null
	@nb=$$($(K) get certificate $(RELEASE)-tls -o jsonpath='{.status.notBefore}'); \
	 st=$$($(K) get pods -l app.kubernetes.io/instance=$(RELEASE) -o jsonpath='{.items[0].status.startTime}'); \
	 if [[ "$$nb" > "$$st" ]]; then echo "Certificate renewed after pod start: restarting"; \
	   $(K) rollout restart deploy/$(RELEASE) >/dev/null; $(K) rollout status deploy/$(RELEASE) --timeout=5m; fi
	@$(MAKE) --no-print-directory ca info

ca: ## Export the private CA to .state/ca.crt
	@$(PREFLIGHT)
	@mkdir -p $(STATE)
	@$(K) get secret $(RELEASE)-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > $(CA_FILE)
	@echo "CA exported: $(CA_FILE)  ($$(openssl x509 -in $(CA_FILE) -noout -subject | sed 's/^subject=//'))"

key: ## Master key -> clipboard (macOS) or .state/<cluster>/master-key (0600); never printed
	@$(PREFLIGHT)
	@$(K) get secret $(RELEASE)-master-key -o jsonpath='{.data.LITELLM_MASTER_KEY}' | base64 -d | { $(call COPY_SECRET,$(STATE)/master-key,Master key); }

client-key: ## Scoped virtual key for an in-cluster client, e.g. make client-key CLIENT=n8n (guarded models only)
	@$(PREFLIGHT)
	@test -n "$(CLIENT)" || { echo "Usage: make client-key CLIENT=n8n"; exit 1; }
	@scripts/client-key.sh $(NS) $(RELEASE) $(CLIENT) $(TEST_PORT)

tunnel: ## Expose the gateway at https://llmgw.localhost:4443 (port-forward; keep open, Ctrl+C ends)
	@$(PREFLIGHT)
	@echo "LiteLLM: $(URL)  (OpenAI-compatible: $(URL)/v1; key: make key; Ctrl+C closes)"
	@$(K) port-forward --address 127.0.0.1 svc/$(RELEASE) $(PORT):443

down: ## Uninstall the gateway; keeps provider keys + master key (PURGE=1 deletes the namespace)
	@$(PREFLIGHT)
	@helm uninstall $(RELEASE) -n $(NS) --wait 2>/dev/null || echo "Release $(RELEASE) not installed."
	@if [ -n "$(PURGE)" ]; then \
	   kubectl delete namespace $(NS) --ignore-not-found --wait; rm -f "$(CA_FILE)"; \
	   echo "Purged namespace $(NS) including stored API keys."; \
	 else \
	   echo "Kept: secrets $(PROVIDER_SECRET) and $(RELEASE)-master-key (make up restores; PURGE=1 deletes)."; \
	 fi

info: ## URL, release, models, guardrails, certificate, pod
	@$(PREFLIGHT)
	@helm status $(RELEASE) -n $(NS) >/dev/null 2>&1 || { echo "Not deployed. Run 'make up'."; exit 1; }
	@echo "  URL          $(URL)/v1   (OpenAI-compatible; needs 'make tunnel'; key: make key)"
	@echo "  Release      $(RELEASE) in namespace $(NS)  ($$(helm list -n $(NS) -f '^$(RELEASE)$$' -o json | jq -r '.[0] | "\(.chart), LiteLLM \(.app_version), rev \(.revision), \(.status)"'))"
	@echo "  Models       $$(helm get values $(RELEASE) -n $(NS) -o json | jq -r '.models | "\(length) OpenRouter free: \(join(", "))"' | cut -c1-150)..."
	@v=$$(helm get values $(RELEASE) -n $(NS) -a -o json); \
	 echo "  Guardrails   Lakera Guard on input (pre_call) + output (post_call), bound per model by the LiteLLM policy engine:"; \
	 echo "                 <id>            block (on_flagged=$$(jq -r .lakera.onFlagged <<<"$$v"))"; \
	 [ "$$(jq -r .variants.monitor <<<"$$v")" = true ] && echo "                 monitor/<id>    detect + log only" || true; \
	 [ "$$(jq -r .variants.unguarded <<<"$$v")" = true ] && echo "                 unguarded/<id>  NO guardrail (comparison demo only)" || true
	@$(K) get certificate $(RELEASE)-tls -o json | jq -r '"  Certificate  ready=\(.status.conditions[]|select(.type=="Ready").status), expires \(.status.notAfter); TLS 1.2/1.3, AES-256-GCM/ChaCha20 only"'
	@echo "  Exposure     ClusterIP only, no Ingress; egress limited to DNS + public HTTPS"
	@echo "  Scope        closed partner-training lab: synthetic lab data only (no Check Point / customer data)"
	@echo "  Example      curl --cacert $(CA_FILE) $(URL)/v1/chat/completions -H \"Authorization: Bearer \$$($(if $(shell command -v pbpaste),pbpaste,cat $(STATE)/master-key))\" \\"
	@echo "                 -H 'Content-Type: application/json' -d '{\"model\":\"$(TEST_MODEL)\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}'"
	@echo "  Pod:"; $(K) get pods -l app.kubernetes.io/instance=$(RELEASE) -o wide | sed 's/^/    /'

test: ca ## Benign vs prompt-injection requests through Lakera, TLS policy, auth, exposure
	@scripts/test.sh $(NS) $(RELEASE) $(GW_HOST) $(TEST_PORT) $(CA_FILE) $(if $(filter vm,$(CLUSTER)),$(VM_DIR),-) $(TEST_MODEL)
