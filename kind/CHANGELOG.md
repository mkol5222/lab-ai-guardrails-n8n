# Changelog

All notable changes to `lab-ai-guardrails-n8n/kind` and `.devcontainer`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.1] - 2026-11-25

### Added
- `tmux` in the devcontainer image (Ubuntu package; rebuild the container to get it).
- Top-level `make n8n-tunnel` runs the n8n tunnel in a background tmux session (`n8n/scripts/tunnel-bg.sh`). A second run
  is a no-op when n8n answers, and restarts the session otherwise. New `make n8n-tunnel-status`, `n8n-tunnel-logs`
  (`TAIL=`, `FOLLOW=1`) and `n8n-tunnel-stop`.

### Changed
- `make up` ends by starting the background tunnel and printing the URL, CA trust step (local only) and the owner login
  (`make n8n-passwd`), so no second terminal is needed.

### Fixed
- Devcontainer image build failed in Codespaces with exit code 141: `k9s version -s | head -1` in `install-tools.sh` could
  SIGPIPE k9s under `set -o pipefail`. Now `awk 'NR==1'`. Verified with a `--no-cache` linux/amd64 build.
- `LAB-DEVCONTAINER-LOCAL.md` cleanup: steps 4 and 5 no longer fail with "'docker stop' requires at least 1 argument" (or a
  `docker inspect` error) when VS Code has already stopped the container, or it is already gone.
- `make -C kind up` failed on devcontainer restart with `Error from server (Forbidden): unknown`. Docker-in-Docker restarts the
  kind node on its own, and `kubectl wait` ran while the API server was still answering 403 before authorization was ready. `up` now
  waits up to 180s for `/readyz` before waiting for the node.

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
