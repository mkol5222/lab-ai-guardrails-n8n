# lab-ai-guardrails-n8n/vm — Ubuntu 26.04 LTS + MicroK8s in Azure, driven by your `az login`.
# Run `make` for the target list.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

STATE      := $(CURDIR)/.state
TF         := terraform -chdir=terraform
SSH_KEY    := $(STATE)/id_ed25519
KNOWN      := $(STATE)/known_hosts
SUB_FILE   := $(STATE)/subscription
VMID_FILE  := $(STATE)/vm_id
KUBECONFIG_LOCAL := $(STATE)/kubeconfig

VM_USER     ?= $(shell echo $(USER) | tr 'A-Z' 'a-z')
# Extra CIDRs (space-separated) allowed besides your current IP, e.g. EXTRA_CIDRS="203.0.113.0/24"
EXTRA_CIDRS ?=
# Local port for `make tunnel` (Kubernetes API on the VM is 16443, never exposed publicly)
TUNNEL_PORT ?= 16443

# Subscription is pinned at first `make up`, so later targets keep working after `az account set`.
SUB      = $$(cat $(SUB_FILE) 2>/dev/null || az account show --query id -o tsv)
TFENV    = ARM_SUBSCRIPTION_ID=$(SUB) TF_VAR_admin_username=$(VM_USER) TF_VAR_ssh_public_key_path=$(SSH_KEY).pub
OUT      = $(TF) output -raw
SSH_OPTS = -i $(SSH_KEY) -o IdentitiesOnly=yes -o UserKnownHostsFile=$(KNOWN) -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10
TARGET   = $$($(OUT) admin_username)@$$($(OUT) public_ip)
VM_ARGS  = --resource-group $$($(OUT) resource_group) --name $$($(OUT) vm_name) --subscription $(SUB)
POWER    = az vm get-instance-view $(VM_ARGS) --query "instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]" -o tsv
NEED_VM  = test -n "$$($(OUT) public_ip 2>/dev/null)" || { echo "No VM. Run 'make up'."; exit 1; }

.PHONY: help up down info ssh serial plan allow stop start pass log status wait k9s tunnel

help: ## Show targets
	@awk 'BEGIN{FS=":.*## "} /^[a-z0-9-]+:.*## /{printf "  \033[1m%-7s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo; echo '  make ssh CMD="kubectl get pods -A"    run one command instead of a shell'

$(SSH_KEY):
	@mkdir -p $(STATE) && chmod 700 $(STATE)
	@ssh-keygen -q -t ed25519 -N "" -C "lab-ai-guardrails-n8n" -f $(SSH_KEY)

$(SUB_FILE):
	@mkdir -p $(STATE)
	@az account show --query id -o tsv > $@.tmp || { rm -f $@.tmp; echo "Not logged in: run 'az login'"; exit 1; }
	@mv $@.tmp $@
	@echo "Subscription: $$(az account show --query name -o tsv)"

terraform/.terraform: terraform/versions.tf
	@$(TF) init -upgrade -input=false >/dev/null && touch $@

# Current public IP as /32 (+ EXTRA_CIDRS) -> TF_VAR_allowed_cidrs
define with_cidrs
ip=$$(curl -fsS --max-time 8 https://api.ipify.org); \
[[ $$ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$$ ]] || { echo "Could not detect public IPv4 (got '$$ip')"; exit 1; }; \
cidrs="\"$$ip/32\""; for c in $(EXTRA_CIDRS); do cidrs="$$cidrs,\"$$c\""; done; \
echo "Allowing SSH/HTTPS from: [$$cidrs]"; \
export TF_VAR_allowed_cidrs="[$$cidrs]";
endef

up: $(SSH_KEY) $(SUB_FILE) terraform/.terraform ## Create/update the VM, wait for MicroK8s to be ready
	@$(with_cidrs) $(TFENV) $(TF) apply -input=false -auto-approve
	@# A rebuilt VM has a new host key: forget the old one (trust-on-first-use per VM instance).
	@id=$$($(OUT) vm_id); [ "$$(cat $(VMID_FILE) 2>/dev/null)" = "$$id" ] || { rm -f $(KNOWN); echo "$$id" > $(VMID_FILE); }
	@$(MAKE) --no-print-directory wait info

plan: $(SSH_KEY) $(SUB_FILE) terraform/.terraform ## Show what `up` would change
	@$(with_cidrs) $(TFENV) $(TF) plan -input=false

allow: $(SSH_KEY) $(SUB_FILE) terraform/.terraform ## Re-point the NSG at your current public IP
	@$(with_cidrs) $(TFENV) $(TF) apply -input=false -auto-approve -target=azurerm_network_security_group.nsg >/dev/null
	@echo "NSG updated."

down: ## Destroy everything (FORCE=1 skips the prompt)
	@$(TFENV) TF_VAR_allowed_cidrs='["127.0.0.1/32"]' $(TF) destroy -input=false $(if $(FORCE),-auto-approve,)
	@rm -f "$(KNOWN)" "$(SUB_FILE)" "$(VMID_FILE)" "$(KUBECONFIG_LOCAL)"

info: ## Show connection details, power state and cost hints
	@$(NEED_VM)
	@printf "  %-14s %s\n" \
	  VM "$$($(OUT) vm_name) ($$($(OUT) vm_size)$$( [ "$$($(OUT) spot)" = true ] && echo ', spot' || true))" \
	  Image "$$($(OUT) image)" \
	  Location "$$($(OUT) location), rg $$($(OUT) resource_group)" \
	  State "$$($(POWER) 2>/dev/null | sed 's|PowerState/||')" \
	  Address "$$($(OUT) public_ip)  ($$($(OUT) fqdn))" \
	  User "$$($(OUT) admin_username)  (SSH key .state/id_ed25519; console password: make pass)" \
	  MicroK8s "$$($(OUT) microk8s_channel)" \
	  Allowed "$$($(TF) output -json allowed_cidrs | tr -d '[]"\n')" \
	  Auto-shutdown "$$($(OUT) auto_shutdown)"
	@echo "  SSH:  make ssh    |  k9s: make k9s    |  console: make serial"
	@echo "  Compute bills only while running ('make stop' deallocates); disk + static IP bill always."

ssh: $(SSH_KEY) ## SSH into the VM (CMD="..." runs a single command)
	@$(NEED_VM)
	@ssh $(SSH_OPTS) $(if $(CMD),,-t) $(TARGET) $(CMD)

k9s: $(SSH_KEY) ## Open k9s on the VM
	@$(NEED_VM)
	@ssh $(SSH_OPTS) -t $(TARGET) k9s

serial: ## Azure serial console (login: make pass; leave: Ctrl+] then q)
	@$(NEED_VM)
	@az extension show -n serial-console >/dev/null 2>&1 || az extension add -n serial-console -y --only-show-errors
	@echo "Login as $$($(OUT) admin_username), password: 'make pass' (copies to clipboard). Press Enter if the prompt does not show."
	@az serial-console connect $(VM_ARGS)

pass: ## Copy the console password to the clipboard
	@$(OUT) admin_password | tr -d '\n' | pbcopy && echo "Console password copied to clipboard."

log: ## Serial boot log (works even when SSH does not)
	@$(NEED_VM)
	@az vm boot-diagnostics get-boot-log $(VM_ARGS) | tail -n $${N:-80}

wait: $(SSH_KEY) ## Wait for SSH + first-boot provisioning to finish
	@$(NEED_VM)
	@echo -n "Waiting for SSH"; for i in $$(seq 60); do ssh $(SSH_OPTS) -o BatchMode=yes $(TARGET) true 2>/dev/null && break; echo -n .; sleep 5; done; echo
	@echo "Waiting for cloud-init (MicroK8s install takes a few minutes)..."
	@ssh $(SSH_OPTS) $(TARGET) 'cloud-init status --wait >/dev/null || true; sudo cat /var/lib/mk8s-setup/status.json 2>/dev/null || echo "{\"done\":false}"'
	@$(MAKE) --no-print-directory status

status: $(SSH_KEY) ## Provisioning result, cluster nodes and pods
	@$(NEED_VM)
	@ssh $(SSH_OPTS) $(TARGET) 'set -e; echo "--- cloud-init: $$(cloud-init status | sed "s/status: //")"; \
	  echo "--- setup: $$(sudo cat /var/lib/mk8s-setup/status.json 2>/dev/null || echo not finished)"; sudo tail -n 5 /var/log/mk8s-setup.log 2>/dev/null || true; \
	  echo "--- versions"; . /etc/os-release; echo "$$PRETTY_NAME"; snap list microk8s 2>/dev/null | tail -1; k9s version -s 2>/dev/null | head -1 || true; jq --version; curl --version | head -1; \
	  echo "--- cluster"; sudo microk8s kubectl get nodes -o wide && sudo microk8s kubectl get pods -A'

tunnel: $(SSH_KEY) ## Local kubectl/k9s: writes .state/kubeconfig, forwards the API via SSH (Ctrl+C ends)
	@$(NEED_VM)
	@ssh $(SSH_OPTS) $(TARGET) 'sudo microk8s config' | sed -E 's#server: https://[^:]+:16443#server: https://127.0.0.1:$(TUNNEL_PORT)#' > $(KUBECONFIG_LOCAL)
	@chmod 600 $(KUBECONFIG_LOCAL)
	@echo "In another terminal:  export KUBECONFIG=$(KUBECONFIG_LOCAL)   (then kubectl / k9s)"
	@echo "Tunnel 127.0.0.1:$(TUNNEL_PORT) -> VM:16443 open; Ctrl+C to close."
	@ssh $(SSH_OPTS) -N -o ExitOnForwardFailure=yes -L 127.0.0.1:$(TUNNEL_PORT):127.0.0.1:16443 $(TARGET)

stop: ## Deallocate the VM (stops compute billing)
	@$(NEED_VM)
	@az vm deallocate $(VM_ARGS) && echo "Deallocated."

start: ## Start the VM and refresh the NSG with your current IP
	@$(NEED_VM)
	@az vm start $(VM_ARGS) && echo "Running."
	@$(MAKE) --no-print-directory allow
