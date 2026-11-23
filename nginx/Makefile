# lab-ai-guardrails-n8n/nginx — pod-name web server over HTTPS (Traefik ingress + cert-manager private CA).
#   CLUSTER=vm     (default) ../vm MicroK8s: https://<vm-fqdn>/ , NSG allows only your IP
#   CLUSTER=docker|kind  Docker Desktop / kind: https://web.localhost:9443/ via `make tunnel`
# Run `make` for the target list.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

include ../common/k8s.mk

STATE     := $(CURDIR)/.state/$(CLUSTER)
CA_FILE   := $(STATE)/ca.crt
NS        ?= web
RELEASE   ?= web
PORT      ?= 9443
TEST_PORT ?= 19443
HELM_ARGS ?=

ifeq ($(CLUSTER),vm)
  HOST = $$(terraform -chdir=$(VM_DIR)/terraform output -raw fqdn)
  URL  = https://$(HOST)/
else
  HOST = web.localhost
  URL  = https://$(HOST):$(PORT)/
endif
K = kubectl -n $(NS)

.PHONY: help up down info test ca addons tunnel

help: ## Show targets (CLUSTER=vm|docker|kind, default vm)
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-7s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo; echo "  Cluster: $(CLUSTER)   (CLUSTER=vm | docker | kind)"

addons: ## Ensure Traefik ingress + cert-manager (part of up)
	@$(PREFLIGHT)
	@$(ENSURE_ADDONS) traefik cert-manager

up: addons ## Deploy/upgrade the chart, wait for pods + certificate, print the URL
ifeq ($(CLUSTER),vm)
	@# Ensure the NSG allows HTTPS from your current IP (port 80 stays closed).
	@$(MAKE) --no-print-directory -C $(VM_DIR) allow
endif
	@helm upgrade --install $(RELEASE) chart -n $(NS) --create-namespace \
	  --set host="$(HOST)" --wait --timeout 5m $(HELM_ARGS)
	@$(K) wait certificate/$(RELEASE)-tls --for=condition=Ready --timeout=120s >/dev/null
	@$(MAKE) --no-print-directory ca info

ca: ## Export the private CA to .state/<cluster>/ca.crt
	@$(PREFLIGHT)
	@mkdir -p $(STATE)
	@$(K) get secret $(RELEASE)-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > $(CA_FILE)
	@echo "CA exported: $(CA_FILE)  ($$(openssl x509 -in $(CA_FILE) -noout -subject | sed 's/^subject=//'))"

tunnel: ## docker/kind: open https://web.localhost:9443/ (port-forward to Traefik; Ctrl+C ends)
ifeq ($(CLUSTER),vm)
	@echo "Not needed on CLUSTER=vm: the site is at $(URL) (NSG allows your IP)."
else
	@$(PREFLIGHT)
	@echo "Site: $(URL)   (trust CA: see 'make info'; Ctrl+C closes)"
	@kubectl -n ingress port-forward --address 127.0.0.1 svc/traefik $(PORT):443
endif

down: ## Uninstall the release and delete the namespace (addons and cluster stay)
	@$(PREFLIGHT)
	@helm uninstall $(RELEASE) -n $(NS) --wait 2>/dev/null || echo "Release $(RELEASE) not installed."
	@kubectl delete namespace $(NS) --ignore-not-found --wait
	@rm -f "$(CA_FILE)"

info: ## URL, release, pods, certificate
	@$(PREFLIGHT)
	@helm status $(RELEASE) -n $(NS) >/dev/null 2>&1 || { echo "Not deployed on '$(CLUSTER)'. Run 'make up CLUSTER=$(CLUSTER)'."; exit 1; }
	@echo "  Cluster      $(CLUSTER)"
	@echo "  URL          $(URL)$(if $(filter-out vm,$(CLUSTER)),   (needs 'make tunnel CLUSTER=$(CLUSTER)'),)"
	@echo "  Release      $(RELEASE) in namespace $(NS)  ($$(helm list -n $(NS) -f '^$(RELEASE)$$' -o json | jq -r '.[0] | "\(.chart), rev \(.revision), \(.status)"'))"
	@$(K) get certificate $(RELEASE)-tls -o json | jq -r '"  Certificate  ready=\(.status.conditions[]|select(.type=="Ready").status), expires \(.status.notAfter), renews \(.status.renewalTime)"'
ifeq ($(CLUSTER),vm)
	@echo "  Access       only from the NSG's allowed CIDRs (make -C ../vm info); port 80 closed"
else
	@echo "  Access       Traefik is ClusterIP only: nothing published on the Mac, only the 127.0.0.1 port-forward"
endif
	@echo "  Trust CA     curl --cacert $(CA_FILE) $(URL)"
	@echo "               macOS browser (on the Mac): sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $(CA_FILE)"
	@echo "  Pods:"; $(K) get pods -l app.kubernetes.io/instance=$(RELEASE) -o wide | sed 's/^/    /'

test: ca ## Verify HTTPS (CA-validated), pod names on the page, TLS >= 1.2, no plain-HTTP exposure
	@scripts/test.sh $(CLUSTER) $(NS) $(RELEASE) "$(HOST)" $(CA_FILE) $(TEST_PORT) $(VM_DIR)
