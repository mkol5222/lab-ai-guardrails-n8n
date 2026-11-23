#!/usr/bin/env bash
# Make sure cluster add-ons exist, the same way on both cluster types.
# Usage: ensure-addons.sh <vm|docker|kind> <vm-dir> <addon>...    addons: cert-manager traefik
#   vm:          MicroK8s addons (`microk8s enable ...` over SSH)
#   docker|kind: the same upstream Helm charts/versions the MicroK8s addons use, pinned below
set -euo pipefail
CLUSTER=$1 VM_DIR=$2; shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
CERT_MANAGER_VERSION=v1.20.2   # = MicroK8s cert-manager addon default
TRAEFIK_CHART_VERSION=39.0.8   # = MicroK8s ingress addon default (Traefik v3.6.13)

microk8s_enable() { make --no-print-directory -C "$VM_DIR" ssh CMD="sudo microk8s enable $1" >/dev/null; }

for addon in "$@"; do
  case $addon in
    cert-manager)
      if ! kubectl -n cert-manager get deploy cert-manager-webhook >/dev/null 2>&1; then
        echo "Installing cert-manager ($CLUSTER)..."
        if [ "$CLUSTER" = vm ]; then microk8s_enable cert-manager; else
          helm upgrade --install cert-manager cert-manager --repo https://charts.jetstack.io \
            --version "$CERT_MANAGER_VERSION" -n cert-manager --create-namespace \
            --set crds.enabled=true --wait --timeout 5m >/dev/null
        fi
      fi
      kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s >/dev/null
      echo "cert-manager: ready"
      ;;
    traefik)
      if ! kubectl -n ingress get pods -l app.kubernetes.io/name=traefik -o name 2>/dev/null | grep -q .; then
        echo "Installing Traefik ingress ($CLUSTER)..."
        if [ "$CLUSTER" = vm ]; then microk8s_enable ingress; else
          helm upgrade --install traefik traefik --repo https://traefik.github.io/charts \
            --version "$TRAEFIK_CHART_VERSION" -n ingress --create-namespace \
            -f "$HERE/traefik-docker.yaml"   # ClusterIP-only Traefik, used for docker and kind --wait --timeout 5m >/dev/null
        fi
      fi
      kubectl -n ingress wait pod -l app.kubernetes.io/name=traefik --for=condition=Ready --timeout=180s >/dev/null
      echo "traefik: ready"
      ;;
    *) echo "unknown addon: $addon" >&2; exit 1 ;;
  esac
done
