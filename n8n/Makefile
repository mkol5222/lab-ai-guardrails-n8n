# lab-ai-guardrails-n8n/n8n — private self-hosted n8n on ../vm MicroK8s (CLUSTER=vm, default) Docker Desktop (CLUSTER=docker) or kind (CLUSTER=kind, devcontainer).
# On vm it deploys through `make tunnel` in ../vm. n8n is NOT exposed outside the cluster (no Ingress,
# no public port); you reach it over `make tunnel` here (kubectl port-forward inside that SSH tunnel).
# Run `make` for the target list.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

include ../common/k8s.mk

STATE     := $(CURDIR)/.state/$(CLUSTER)
CA_FILE   := $(STATE)/ca.crt
NS        ?= n8n
RELEASE   ?= n8n
N8N_HOST  ?= n8n.localhost
PORT      ?= 8443
TEST_PORT ?= 18443
HELM_ARGS ?=
# In-cluster LLM gateway (../llmgw) used by `make llm-connect` / `make llm-test`
GW_NS     ?= llmgw
GW_REL    ?= llmgw
LLM_MODEL ?= google/gemma-4-31b-it:free
WORKFLOW  ?= workflows/llmgw-chat-agent.json

URL     = https://$(N8N_HOST):$(PORT)/
K       = kubectl -n $(NS)

.PHONY: help up down info test tunnel ca addons llm-connect llm-test

help: ## Show targets
	@echo "  Cluster: $(CLUSTER)   (CLUSTER=vm | docker | kind)"; echo
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-7s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

addons: ## Ensure cert-manager (MicroK8s addon on vm, Helm chart on docker/kind; part of up)
	@$(PREFLIGHT)
	@$(ENSURE_ADDONS) cert-manager

up: addons ## Deploy/upgrade n8n, wait until ready, print the URL
	@# Trust the llmgw CA if `make llm-connect` provided it (ConfigMap llmgw-ca).
	@ca=$$({ $(K) get configmap llmgw-ca -o name 2>/dev/null || true; } | cut -d/ -f2); \
	 helm upgrade --install $(RELEASE) chart -n $(NS) --create-namespace \
	  --set host=$(N8N_HOST) --set localPort=$(PORT) --set extraCA.configMap=$$ca --wait --timeout 10m $(HELM_ARGS)
	@$(K) wait certificate/$(RELEASE)-tls --for=condition=Ready --timeout=120s >/dev/null
	@# n8n loads its certificate at start: restart once if cert-manager renewed it since.
	@nb=$$($(K) get certificate $(RELEASE)-tls -o jsonpath='{.status.notBefore}'); \
	 st=$$($(K) get pods -l app.kubernetes.io/instance=$(RELEASE) -o jsonpath='{.items[0].status.startTime}'); \
	 if [[ "$$nb" > "$$st" ]]; then echo "Certificate renewed after pod start: restarting n8n"; \
	   $(K) rollout restart deploy/$(RELEASE) >/dev/null; $(K) rollout status deploy/$(RELEASE) --timeout=5m; fi
	@$(MAKE) --no-print-directory ca info

ca: ## Export the private CA to .state/ca.crt
	@$(PREFLIGHT)
	@mkdir -p $(STATE)
	@$(K) get secret $(RELEASE)-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > $(CA_FILE)
	@echo "CA exported: $(CA_FILE)  ($$(openssl x509 -in $(CA_FILE) -noout -subject | sed 's/^subject=//'))"

llm-connect: ## Wire n8n to in-cluster llmgw: CA trust, credential "llmgw (Lakera-guarded)", import WORKFLOW
	@$(PREFLIGHT)
	@scripts/llm-connect.sh $(NS) $(RELEASE) $(GW_NS) $(GW_REL) $(WORKFLOW)
	@$(MAKE) --no-print-directory up >/dev/null && echo "n8n restarted with the llmgw CA trusted. Open $(URL) (make tunnel)."

llm-test: ## From inside the n8n pod: TLS, key scope, benign vs injection via Lakera, Responses API refused
	@$(PREFLIGHT)
	@scripts/llm-test.sh $(NS) $(RELEASE) $(GW_NS) $(GW_REL) $(LLM_MODEL) $$(helm get values $(RELEASE) -n $(NS) -a -o json | jq -r '"\(.image.repository):\(.image.tag)"')

tunnel: ## Open n8n at https://n8n.localhost:8443/ (port-forward; keep open, Ctrl+C ends)
	@$(PREFLIGHT)
	@echo "n8n: $(URL)   (trust the CA once, see 'make info'; Ctrl+C closes)"
	@$(K) port-forward --address 127.0.0.1 svc/$(RELEASE) $(PORT):443

down: ## Uninstall n8n; keeps data + encryption key (PURGE=1 deletes the namespace and everything)
	@$(PREFLIGHT)
	@helm uninstall $(RELEASE) -n $(NS) --wait 2>/dev/null || echo "Release $(RELEASE) not installed."
	@if [ -n "$(PURGE)" ]; then \
	   kubectl delete namespace $(NS) --ignore-not-found --wait; rm -f "$(CA_FILE)"; \
	   echo "Purged: workflows, credentials and encryption key are gone."; \
	 else \
	   echo "Kept: PVC $(RELEASE)-data and secret $(RELEASE)-encryption-key in namespace $(NS) (make up restores; PURGE=1 deletes)."; \
	 fi

info: ## URL, release, pod, certificate, exposure
	@$(PREFLIGHT)
	@helm status $(RELEASE) -n $(NS) >/dev/null 2>&1 || { echo "Not deployed. Run 'make up'."; exit 1; }
	@echo "  URL          $(URL)   (needs 'make tunnel' running)"
	@echo "  Release      $(RELEASE) in namespace $(NS)  ($$(helm list -n $(NS) -f '^$(RELEASE)$$' -o json | jq -r '.[0] | "\(.chart), app \(.app_version), rev \(.revision), \(.status)"'))"
	@$(K) get certificate $(RELEASE)-tls -o json | jq -r '"  Certificate  ready=\(.status.conditions[]|select(.type=="Ready").status), SANs \(.spec.dnsNames|join(",")),127.0.0.1, expires \(.status.notAfter)"'
	@echo "  Data         PVC $$($(K) get pvc $(RELEASE)-data -o jsonpath='{.spec.resources.requests.storage} ({.status.phase})'), encryption key in secret $(RELEASE)-encryption-key"
	@echo "  Exposure     ClusterIP only, no Ingress: reachable only through the SSH tunnel"
	@echo "  Trust CA     curl --cacert $(CA_FILE) $(URL)healthz"
	@echo "               macOS browser (on the Mac): sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $(CA_FILE)"
	@echo "  First visit  create the owner account on the setup screen"
	@echo "  Pod:"; $(K) get pods -l app.kubernetes.io/instance=$(RELEASE) -o wide | sed 's/^/    /'

test: ca ## Verify CA-validated HTTPS, health, TLS >= 1.2, and that n8n is not publicly exposed
	@fail=0; pf_log=$(STATE)/pf-test.log; \
	$(K) port-forward --address 127.0.0.1 svc/$(RELEASE) $(TEST_PORT):443 >$$pf_log 2>&1 & pf=$$!; \
	trap 'kill $$pf 2>/dev/null || true' EXIT; \
	for i in $$(seq 30); do grep -q Forwarding $$pf_log && break; sleep 0.5; done; \
	c="curl -sS --max-time 15 --tlsv1.2 --cacert $(CA_FILE) --resolve $(N8N_HOST):$(TEST_PORT):127.0.0.1"; \
	h=$$($$c https://$(N8N_HOST):$(TEST_PORT)/healthz) || { echo "FAIL  HTTPS /healthz: $$h"; exit 1; }; \
	if [ "$$(jq -r .status <<<"$$h")" = ok ]; then echo "PASS  HTTPS /healthz ok, certificate verified against the private CA"; else echo "FAIL  /healthz: $$h"; fail=1; fi; \
	code=$$($$c -o $(STATE)/index.html -w '%{http_code}' https://$(N8N_HOST):$(TEST_PORT)/); \
	if [ "$$code" = 200 ] && grep -qi 'n8n' $(STATE)/index.html; then echo "PASS  editor UI served (HTTP $$code)"; else echo "FAIL  editor UI (HTTP $$code)"; fail=1; fi; \
	out=$$(openssl s_client -connect 127.0.0.1:$(TEST_PORT) -servername $(N8N_HOST) -tls1_1 -cipher 'DEFAULT:@SECLEVEL=0' </dev/null 2>&1 || true); \
	if grep -q 'alert protocol version' <<<"$$out"; then echo "PASS  TLS 1.1 rejected by server"; \
	elif grep -qE 'Cipher is [A-Z0-9]' <<<"$$out" && ! grep -q 'Cipher is (NONE)' <<<"$$out"; then echo "FAIL  TLS 1.1 accepted"; fail=1; \
	else echo "SKIP  TLS 1.1 probe inconclusive"; fi; \
	ing=$$({ $(K) get ingress -o name; $(K) get ingressroutes.traefik.io -o name 2>/dev/null; $(K) get httproutes.gateway.networking.k8s.io -o name 2>/dev/null; } | wc -l | tr -d ' '); \
	ext=$$($(K) get svc -o jsonpath='{range .items[?(@.spec.type!="ClusterIP")]}{.metadata.name} {end}'); \
	if [ "$$ing" = 0 ] && [ -z "$$ext" ]; then echo "PASS  no Ingress / IngressRoute / HTTPRoute / NodePort / LoadBalancer in namespace $(NS)"; else echo "FAIL  exposed: ingresses=$$ing services=$$ext"; fail=1; fi; \
	if [ "$(CLUSTER)" = vm ]; then \
	  pip=$$(terraform -chdir=$(VM_DIR)/terraform output -raw public_ip); \
	  iss=$$(openssl s_client -connect $$pip:443 -servername $(N8N_HOST) </dev/null 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true); \
	  if grep -q "$$(openssl x509 -in $(CA_FILE) -noout -subject | sed 's/^subject=//')" <<<"$$iss"; then echo "FAIL  VM public IP presents the n8n certificate"; fail=1; \
	  else echo "PASS  VM public IP does not serve n8n (issuer seen: $${iss:-no TLS answer})"; fi; \
	else echo "SKIP  public-IP probe (CLUSTER=$(CLUSTER) has no public address)"; fi; \
	echo "INFO  pod restarts: $$($(K) get pods -l app.kubernetes.io/instance=$(RELEASE) -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')"; \
	echo; echo "URL: $(URL)  (run 'make tunnel')"; exit $$fail
