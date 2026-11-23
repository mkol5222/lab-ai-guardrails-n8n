# Changelog

All notable changes to `lab-ai-guardrails-n8n/llmgw`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-11-23

### Added
- Postgres 18.7 native sidecar (loopback only, PVC `llmgw-db` kept on uninstall) to back scoped virtual keys. `LITELLM_SALT_KEY` and `POSTGRES_PASSWORD` are generated in-cluster.
- `make client-key CLIENT=<name>`: scoped virtual key (guarded models only, rate limits, no admin) stored in Secret `llmgw-client-<name>`.
- In-cluster clients: certificate SANs `llmgw.llmgw.svc[.cluster.local]`, and the NetworkPolicy admits `clients.namespaces` (default n8n) on 8443.
- nginx route allowlist: only `/v1/chat/completions`, `/v1/models`, `/health/*` and `/key/*`. Everything else returns 403, so Lakera cannot be bypassed through the Responses API, Messages API and similar.
- `make test` checks that the non-guarded endpoints are refused.
- Rate-limit fallback (`fallbackModel`, default `openrouter/free`): on 429 or provider errors a request is retried on the fallback **within the same variant** (`<id>` to `openrouter/free`, `monitor/<id>` to `monitor/openrouter/free`), so the guardrail mode is kept.

### Changed
- The Deployment uses RollingUpdate with maxSurge 0 (one pod at a time for the RWO database volume; Helm 4 server-side apply would not switch an existing Deployment to Recreate).
- The LiteLLM UI is no longer reachable (blocked by the allowlist).

## [0.2.0] - 2026-11-23

### Added
- `CLUSTER=docker`: deploy to Docker Desktop Kubernetes. The default stays `CLUSTER=vm`.
- `make test` now checks in the gateway log that Lakera detected the injection on the `monitor/` variant.

### Changed
- cert-manager handling moved to the shared `../common/ensure-addons.sh`. State (CA, models) moved to `.state/<cluster>/`.
- Verified end to end on the vm cluster: benign prompt answered, injection blocked (HTTP 400), monitor variant logged and passed.

## [0.1.0] - 2026-11-23

### Added
- Helm chart `llmgw`: LiteLLM v1.110.2 (non-root image) proxy serving the OpenRouter free text models, with the list
  refreshed from the public catalog on every `make up`, plus the `openrouter/free` router.
- Check Point Lakera Guard (`lakera_v2`) on input (`pre_call`) and output (`post_call`), bound per model by the LiteLLM
  policy engine. Model variants: `<id>` (block), `monitor/<id>` (log only), and opt-in `unguarded/<id>` (`UNGUARDED=1`, comparison demos only).
- `make secrets`: interactive hidden-input prompt for the OpenRouter key, Lakera key and project. Validates them against both
  APIs and stores them in a Kubernetes Secret without putting them on argv, in files or in output.
- nginx TLS sidecar: TLS 1.2/1.3 with AES-256-GCM and ChaCha20-Poly1305 only, plus HSTS. Certificate from a cert-manager private CA.
- ClusterIP only, NetworkPolicy (no pod ingress; egress DNS + public 443), message logging and telemetry off.
- Makefile targets `secrets`, `up`, `down` (`PURGE=1`), `info`, `test`, `tunnel`, `key`, `models`, `ca`.
- `make test`: benign prompt allowed, prompt injection blocked by Lakera, monitor variant passes, TLS policy, auth, exposure.
