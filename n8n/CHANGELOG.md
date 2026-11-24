# Changelog

All notable changes to `lab-ai-guardrails-n8n/n8n`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.4.0] - 2026-11-24

### Added
- Pre-created n8n instance owner account (`guru@example.com`, `Guru Lab`) via `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true` (chart v0.2.0).
- `templates/owner-secret.yaml`: generates a random 24-character password and bcrypt hash once in-cluster (reused on upgrade via `lookup`, kept on uninstall via `helm.sh/resource-policy: keep`). The pod mounts only `password_hash`.
- `make passwd` (also exposed at repo root as `make n8n-passwd`) to display the pre-created owner email and generated password.
- `make test` checks that the owner setup wizard is bypassed (`showSetupOnFirstLoad=false`) and verifies login via `POST /rest/login` (credentials piped via stdin, never on argv).

## [0.3.1] - 2026-11-23

### Fixed
- `make up` on a fresh cluster: the `llmgw-ca` ConfigMap lookup failed while the `n8n` namespace didn't exist yet (pipefail).

### Added
- `CLUSTER=kind` (devcontainer).

## [0.3.0] - 2026-11-23

### Added
- `extraCA.configMap`: trust an extra CA through `NODE_EXTRA_CA_CERTS`, used for the llmgw private CA. `make up` picks up ConfigMap `llmgw-ca` automatically.
- `make llm-connect`: CA ConfigMap, the credential "llmgw (Lakera-guarded)" holding the scoped key (piped, never printed), and the workflow import.
- `make llm-test`: n8n-to-llmgw checks from inside the n8n pod, plus a NetworkPolicy probe from another namespace.
- `workflows/llmgw-chat-agent.json`: reusable chat agent workflow on `google/gemma-4-31b-it:free` with the Responses API off.

## [0.2.0] - 2026-11-23

### Added
- `CLUSTER=docker`: deploy to Docker Desktop Kubernetes (cert-manager from the Helm chart). The default stays `CLUSTER=vm`.

### Changed
- cert-manager handling moved to the shared `../common/ensure-addons.sh`. State (CA) moved to `.state/<cluster>/`. The public-IP probe runs on vm only.

## [0.1.0] - 2026-11-23

### Added
- Helm chart `n8n-private`: a single n8n 2.48.7 instance on SQLite with a 5Gi PVC and a Recreate strategy.
- HTTPS served by n8n itself, with a certificate from a cert-manager private CA (SANs `n8n.localhost`, `localhost`, `127.0.0.1`).
- No Ingress and a ClusterIP Service only. Access is through `make tunnel` (kubectl port-forward over the `../vm` SSH tunnel).
- `N8N_ENCRYPTION_KEY` generated in-cluster, reused on upgrade, kept on uninstall (`helm.sh/resource-policy: keep`).
- Hardened pod. Telemetry, version notifications, community packages and the AI assistant are disabled. A NetworkPolicy denies in-cluster ingress.
- Makefile targets `up`, `down` (`PURGE=1`), `info`, `test`, `tunnel`, `ca`, `addons`.
- `make test`: CA-verified HTTPS health and UI, server-side TLS 1.1 rejection, no exposure objects, public IP not serving n8n.
