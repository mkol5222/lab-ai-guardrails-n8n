# Changelog

All notable changes to `lab-ai-guardrails-n8n/nginx`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-11-23

### Added
- `CLUSTER=docker`: deploy to Docker Desktop Kubernetes. Traefik and cert-manager are installed from the same Helm chart versions the MicroK8s add-ons use, with Traefik on ClusterIP only, plus `make tunnel` for https://web.localhost:9443/.
- A shared `../common/k8s.mk` (cluster selection, preflight) and `../common/ensure-addons.sh`.
- `make test` moved to `scripts/test.sh` and handles both clusters. The port-80 check is now a TCP probe (no plain-HTTP request).

### Changed
- State (CA) moved to `.state/<cluster>/`.

## [0.1.0] - 2026-11-23

### Added
- Helm chart `podname-web`: nginx-unprivileged homepage showing the serving pod's name (`/`, `/pod`, `X-Pod-Name`).
- TLS from a cert-manager self-signed CA (selfSigned Issuer -> CA -> host certificate, auto-renewed).
- Traefik Ingress on `websecure` only. NetworkPolicy allows traffic only from the ingress namespace. Hardened pod security context.
- Makefile targets `up`, `down`, `info`, `test` (+ `ca`, `addons`), deploying through `../vm` `make tunnel`.
- `make test`: CA-verified HTTPS, pod-name check across replicas, server-side TLS 1.1 rejection, port 80 closed.

### Changed
- Switched from a Let's Encrypt (ACME HTTP-01) design to a self-signed CA, because HTTP-01 needs inbound
  access from the whole Internet and access here is limited to the operator IP.
