# Changelog

All notable changes to `lab-ai-guardrails-n8n/kind` and `.devcontainer`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-11-24

### Added
- Top-level `Makefile` with `make up` (validates running inside the devcontainer, runs the full `kind` → `n8n` → `llmgw` → connect/test flow, and prints browser + login instructions), `make n8n-passwd`, `make n8n-tunnel`, and `make down`.
- `DEVCONTAINER=true` in `.devcontainer/devcontainer.json` `containerEnv` alongside `CLUSTER=kind`.

## [0.1.1] - 2026-11-23

### Changed
- `hostRequirements.memory` lowered from 8gb to 6gb. Docker Desktop at "8 GB" reports about 7.65 GiB, and VS Code warned that the
  host requirements were not met. The measured full lab is about 3.5 GiB.

## [0.1.0] - 2026-11-23

### Added
- Devcontainer (`.devcontainer/`): Ubuntu 24.04 base, Docker-in-Docker, and SHA-256-verified kubectl v1.36.2, Helm v4.3.2,
  kind v0.33.0 and k9s v0.51.0. Sets `CLUSTER=kind`, forwards 8443/4443/9443, and runs `make -C kind up` on start.
- `kind/Makefile`: `up` (create, or restart after a container restart), `down`, `info`, `k9s`. Single node, API on 127.0.0.1,
  no host port mappings.
- `CLUSTER=kind` in `common/k8s.mk` (kubeconfig `.state/kind.kubeconfig`, 0600). Add-ons come from the same pinned Helm charts as on docker.
- Portable secret hand-off (`COPY_SECRET`): clipboard on macOS, otherwise a 0600 file. Never printed.

### Verified
- In the local devcontainer on Docker Desktop (arm64): kind v1.37.0 node. `nginx` test (4 PASS) and `n8n` test (4 PASS, public-IP probe SKIP).
