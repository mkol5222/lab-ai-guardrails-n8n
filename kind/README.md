# kind — the lab in a devcontainer (or on any host with Docker + kind)

The third way to run the lab, next to the Azure VM ([`../vm`](../vm), `CLUSTER=vm`) and Docker Desktop Kubernetes
(`CLUSTER=docker`). A [kind](https://kind.sigs.k8s.io/) cluster named `mk8s-lab` runs in **Docker-in-Docker inside the
devcontainer** ([`../.devcontainer`](../.devcontainer)), so the host needs nothing but Docker. The devcontainer sets
`CLUSTER=kind` for every terminal.

## Start

- **VS Code:** open the repository folder and run **Dev Containers: Reopen in Container**.
- **CLI:** `devcontainer up --workspace-folder .`, then `devcontainer exec --workspace-folder . bash`.

The first build takes about 3–5 minutes. `postStartCommand` runs `make -C kind up`, which creates the cluster, or restarts it after
the container restarts. After that, follow [`../LAB-GUIDE.md`](../LAB-GUIDE.md). `export CLUSTER=...` isn't needed, because
the container already sets it.

## Targets

| Target | What it does |
|---|---|
| `make -C kind up` | Creates `mk8s-lab` (single node, API on 127.0.0.1, no host port mappings) or starts its stopped node. Writes `.state/kind.kubeconfig` (0600) |
| `make -C kind info` | Node, version, architecture, Helm releases |
| `make -C kind k9s` | k9s on the cluster |
| `make -C kind down` | Deletes the cluster and everything in it |

## What the devcontainer contains

`mcr.microsoft.com/devcontainers/base:ubuntu-24.04` plus Docker-in-Docker, and these tools, pinned and **SHA-256-verified** at
build time (`.devcontainer/install-tools.sh`): kubectl v1.36.2, Helm v4.3.2, kind v0.33.0 and k9s v0.51.0. Also make, jq,
openssl, curl, netcat and dig. It builds for amd64 and arm64.

## Reaching the apps

`make -C n8n tunnel` (and the llmgw and nginx tunnels) binds `127.0.0.1` **inside the container**. VS Code forwards the
ports to your Mac: 8443 n8n, 4443 llmgw, 9443 nginx. So `https://n8n.localhost:8443/` works in the host browser exactly as with
Docker Desktop. The bare devcontainer CLI doesn't forward ports; there, use the apps from the container terminal.

Trust a CA **on the Mac** (the workspace is bind-mounted, so the file is in your checkout):

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain lab-ai-guardrails-n8n/n8n/.state/kind/ca.crt
```

There is no clipboard inside the container: `make -C llmgw key` writes `llmgw/.state/kind/master-key` (mode 0600)
instead. Use it as `$(cat llmgw/.state/kind/master-key)`.

## Notes

- Resources: the full lab uses about 3.5 GiB of RAM. `hostRequirements` asks for 4 CPUs, 6 GB RAM and 32 GB disk, so a Docker Desktop VM set to 8 GB (reported as about 7.65 GiB) passes.
- NetworkPolicy: kind's default CNI (kindnet) enforces it, and `make -C n8n llm-test` probes for that.
- GitHub Codespaces is the next step. The same container works there, but Codespaces looks for `.devcontainer/` at the repo
  root and forwards ports through `*.app.github.dev` URLs, so the n8n host name needs adapting.
