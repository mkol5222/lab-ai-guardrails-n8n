#!/usr/bin/env bash
# Install pinned CLI tools, each verified against its publisher's SHA-256 checksum. Runs at image build.
set -euo pipefail
: "${KUBECTL_VERSION:?}" "${HELM_VERSION:?}" "${KIND_VERSION:?}" "${K9S_VERSION:?}"
arch=$(dpkg --print-architecture)            # amd64 | arm64
tmp=$(mktemp -d); cd "$tmp"
get() { curl -fsSL --retry 3 -o "$1" "$2"; }

# kubectl (dl.k8s.io publishes the bare hash)
get kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
get kubectl.sha256 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -
install -m 0755 kubectl /usr/local/bin/kubectl

# helm
f="helm-${HELM_VERSION}-linux-${arch}.tar.gz"
get "$f" "https://get.helm.sh/$f"; get "$f.sha256sum" "https://get.helm.sh/$f.sha256sum"
sha256sum -c "$f.sha256sum"
tar -xzf "$f" "linux-${arch}/helm"; install -m 0755 "linux-${arch}/helm" /usr/local/bin/helm

# kind
f="kind-linux-${arch}"
get "$f" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/$f"
get "$f.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/$f.sha256sum"
sha256sum -c "$f.sha256sum"
install -m 0755 "$f" /usr/local/bin/kind

# k9s
f="k9s_Linux_${arch}.tar.gz"
get "$f" "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/$f"
get checksums.sha256 "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256"
grep -E "  ${f}\$" checksums.sha256 | sha256sum -c -
tar -xzf "$f" k9s; install -m 0755 k9s /usr/local/bin/k9s

cd /; rm -rf "$tmp"
kubectl version --client=true -o json | jq -r '"kubectl " + .clientVersion.gitVersion'
helm version --short; kind version; k9s version -s | head -1
