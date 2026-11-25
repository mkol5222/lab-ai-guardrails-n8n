# Changelog

All notable changes to `lab-ai-guardrails-n8n/n8n`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.6.0] - 2026-11-25

### Fixed
- Codespaces: the chat panel and live editor updates broke because GitHub's port forwarder rewrites `Origin` to
  `https://localhost:8443` while sending `X-Forwarded-Host: <codespace>-8443.app.github.dev`, so n8n refused every push
  connection ("Origin header does NOT match the expected origin").

### Added
- Chart v0.4.0: optional `originProxy` nginx sidecar (`nginx-unprivileged:1.31.7-alpine`, TLS 1.2/1.3, non-root, read-only
  root filesystem). It pins `X-Forwarded-Host`, maps only the `allowedOrigins` to the canonical origin, proxies websockets, and
  connects to n8n over loopback TLS verified with the private CA. The Service targets the sidecar when it is enabled.
  `make up` turns it on only when `CODESPACE_NAME` is set.

### Verified
- Local devcontainer (rebuilt from scratch, arm64): n8n deploys without the sidecar (one container, Service targets n8n),
  `make -C n8n test` 7 PASS + 1 SKIP, background tunnel healthy.
- Codespaces: the pod ran n8n + origin-proxy (2/2), browser traffic passed through the sidecar, and n8n logged no origin
  errors. The end-to-end chat check in a fresh codespace is still pending.

## [0.5.2] - 2026-11-25

### Added
- `scripts/tunnel-bg.sh start|status|logs|stop`: `make tunnel` in a tmux session under a loop that restarts the port-forward
  when it exits (for example after `llm-connect` restarts the pod). Health is `/healthz` over TLS verified with the n8n CA.
  Log in the gitignored `.state/n8n-tunnel.log` (0600). Used by the top-level `make n8n-tunnel*` targets.

### Documentation
- Troubleshooting for `Prompt Roulette V2` failing in `Get Split Info`: host web filtering can reset TLS to
  `datasets-server.huggingface.co` for Docker Desktop traffic while the Mac itself can reach it. Includes a `curl` check and fixes
  (README, `LAB-GUIDE.md`, `LAB-DEVCONTAINER-LOCAL.md`).

## [0.5.1] - 2026-11-24

### Added
- `workflows/llmgw-chat-agent-lakera-precheck.json`: forked chat agent workflow with an upfront Lakera Guard v2 API check (`POST https://api.lakera.ai/v2/guard`) that replies `"lakera says there is issue."` when flagged before calling the AI Agent.
- `make llm-connect` now supports multiple `WORKFLOWS` (pre-installing both lab chat workflows by default, keeping `WORKFLOW=` backward-compatible) and pre-populates the shared `LakeraAPI` Bearer credential (`dwOBu8Lap8nw2gG9`, also used by `Prompt Roulette V2`) and `lakera_project_id` in-memory from `llmgw-provider-keys`.

## [0.5.0] - 2026-11-24

### Added
- Declarative instance-level MCP enablement (`mcp.enabled: true`, chart v0.3.0): sets `N8N_MCP_MANAGED_BY_ENV=true` and `N8N_MCP_ACCESS_ENABLED=true` so `/mcp-server/http` is enabled automatically on startup.
- `make test` verifies `/mcp-server/http` responds with `HTTP 401` and `WWW-Authenticate: Bearer realm="n8n MCP Server"` when `mcp.enabled=true`.
- Bundled lab workflows from `mkol5222/lakera-in-n8n` stored locally in `workflows/get-public-ip.json` and `workflows/prompt-roulette.json`.
- `scripts/import-workflows.sh` and `make import-workflows` (run automatically during `make up`) to import the bundled workflows idempotently into the running n8n pod.

## [0.4.0] - 2026-11-24

### Added
- Pre-created n8n instance owner account (`guru@example.com`, `Guru Lab`) via `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true` (chart v0.2.0).
- `templates/owner-secret.yaml`: generates a random 24-character password and bcrypt hash once in-cluster (reused on upgrade via `lookup`, kept on uninstall via `helm.sh/resource-policy: keep`). The pod mounts only `password_hash`.
- `make passwd` (also exposed at repo root as `make n8n-passwd`) to display the pre-created owner email and generated password.
- `make test` checks that the owner setup wizard is bypassed (`showSetupOnFirstLoad=false`) and verifies login via `POST /rest/login` (credentials piped via stdin, never on argv).

### Fixed
- `make test` on fresh clusters without Traefik / Gateway API CRDs: guard optional `ingressroutes.traefik.io` and `httproutes.gateway.networking.k8s.io` lookups with `|| true` under `set -euo pipefail`.

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
