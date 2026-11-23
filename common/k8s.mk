# Shared cluster selection for the nginx / n8n / llmgw Makefiles (included, not run directly).
#   CLUSTER=vm      (default) MicroK8s on the Azure VM in ../vm, reached via `make -C vm tunnel`
#   CLUSTER=docker  Kubernetes in Docker Desktop (context docker-desktop)
#   CLUSTER=kind    kind cluster (e.g. inside the devcontainer, which sets CLUSTER=kind), see ../kind
# The choice can also be exported:  export CLUSTER=docker

CLUSTER    ?= vm
COMMON_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT_DIR   := $(abspath $(COMMON_DIR)/..)
VM_DIR     := $(ROOT_DIR)/vm
DD_CONTEXT ?= docker-desktop
KIND_CLUSTER ?= mk8s-lab

ifeq ($(CLUSTER),vm)
  export KUBECONFIG := $(VM_DIR)/.state/kubeconfig
  CLUSTER_HINT := Start the API tunnel in another terminal:  make -C $(VM_DIR) tunnel
  # Refresh nothing: the vm tunnel writes the kubeconfig.
  KUBECONFIG_REFRESH := true
else ifeq ($(CLUSTER),docker)
  # Private single-context copy of the Docker Desktop credentials (gitignored .state/).
  export KUBECONFIG := $(ROOT_DIR)/.state/docker-desktop.kubeconfig
  CLUSTER_HINT := Enable Kubernetes in Docker Desktop (Settings > Kubernetes > Enable Kubernetes) and wait until it is running.
  KUBECONFIG_REFRESH := mkdir -p $(ROOT_DIR)/.state && chmod 700 $(ROOT_DIR)/.state && \
	KUBECONFIG=$(HOME)/.kube/config kubectl config view --minify --flatten --context $(DD_CONTEXT) > $(KUBECONFIG).tmp 2>/dev/null && \
	chmod 600 $(KUBECONFIG).tmp && mv $(KUBECONFIG).tmp $(KUBECONFIG) || rm -f $(KUBECONFIG).tmp
else ifeq ($(CLUSTER),kind)
  export KUBECONFIG := $(ROOT_DIR)/.state/kind.kubeconfig
  CLUSTER_HINT := Create/start the kind cluster:  make -C $(ROOT_DIR)/kind up
  KUBECONFIG_REFRESH := mkdir -p $(ROOT_DIR)/.state && chmod 700 $(ROOT_DIR)/.state && \
	kind get kubeconfig --name $(KIND_CLUSTER) > $(KUBECONFIG).tmp 2>/dev/null && \
	chmod 600 $(KUBECONFIG).tmp && mv $(KUBECONFIG).tmp $(KUBECONFIG) || rm -f $(KUBECONFIG).tmp
else
  $(error CLUSTER must be 'vm', 'docker' or 'kind' (got '$(CLUSTER)'))
endif

PREFLIGHT = command -v helm >/dev/null || { echo "helm not found: brew install helm"; exit 1; }; \
	$(KUBECONFIG_REFRESH); \
	test -s "$(KUBECONFIG)" && kubectl version --request-timeout=5s >/dev/null 2>&1 || \
	{ echo "Cluster '$(CLUSTER)' not reachable via $(KUBECONFIG)."; echo "$(CLUSTER_HINT)"; exit 1; }

ENSURE_ADDONS = $(COMMON_DIR)/ensure-addons.sh $(CLUSTER) $(VM_DIR)

# Copy a secret value (stdin) for the user: clipboard on macOS, else a 0600 file (never printed).
# $(call COPY_SECRET,<file>,<label>)
COPY_SECRET = if command -v pbcopy >/dev/null; then pbcopy && echo "$(2) copied to clipboard."; \
	else mkdir -p $(dir $(1)) && (umask 077; cat > $(1)) && echo "$(2) written to $(1) (mode 600). Use it as \$$(cat $(1))"; fi
