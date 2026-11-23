# lab-ai-guardrails-n8n

**Hands-on lab:** an n8n AI agent whose LLM traffic goes only through a private LiteLLM gateway protected by
**Check Point Lakera Guard (AI Guardrails)**. It shows a benign prompt being answered and a prompt injection being blocked.

> Community training lab for partner enablement. It is **not an official Check Point product** and has no support.
> Use synthetic prompts only. The LLMs are OpenRouter free models, and you bring your own OpenRouter and Lakera keys.

| Form factor | Guide | Needs on your machine |
|---|---|---|
| GitHub Codespaces | [LAB-CODESPACES.md](LAB-CODESPACES.md) | a browser |
| Local devcontainer (kind) | [LAB-DEVCONTAINER-LOCAL.md](LAB-DEVCONTAINER-LOCAL.md) | Docker + VS Code |
| Docker Desktop Kubernetes | [LAB-GUIDE.md](LAB-GUIDE.md) | Docker Desktop, helm, jq |
| Azure VM (MicroK8s) | [vm/README.md](vm/README.md), then LAB-GUIDE with `CLUSTER=vm` | az, terraform, helm |

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/mkol5222/lab-ai-guardrails-n8n)

## Repository layout

The lab is make-driven, and each app is its own Helm chart. Clusters: kind (devcontainer and Codespaces), Docker Desktop
Kubernetes, or a MicroK8s VM on Azure.

| Folder | What it is |
|---|---|
| [`vm/`](vm) | Terraform + Makefile: an Ubuntu 26.04 LTS Azure VM with MicroK8s, k9s, jq and curl. `make up / down / info / ssh / serial / tunnel` |
| [`nginx/`](nginx) | Pod-name web server over HTTPS (Traefik ingress, cert-manager private CA) |
| [`n8n/`](n8n) | Private self-hosted n8n over CA-signed HTTPS, no ingress, reached through a tunnel |
| [`llmgw/`](llmgw) | Private LiteLLM gateway to OpenRouter free models, protected by Check Point Lakera Guard |
| [`kind/`](kind) + [`.devcontainer/`](.devcontainer) | The lab in a devcontainer: a kind cluster in Docker-in-Docker, so the host needs nothing but Docker |
| [`common/`](common) | Shared cluster selection (`k8s.mk`) and add-on installer (`ensure-addons.sh`) |

## Choosing the cluster

Every app Makefile takes `CLUSTER=vm` (the default), `CLUSTER=docker` or `CLUSTER=kind` (set automatically in the devcontainer):

```bash
# Devcontainer / Codespaces: CLUSTER=kind is preset
make -C n8n up && make -C n8n test

# Azure VM
make -C vm up && make -C vm tunnel          # keep the tunnel open
make -C n8n up && make -C n8n test

# Docker Desktop (enable Settings > Kubernetes first)
make -C n8n up CLUSTER=docker && make -C n8n test CLUSTER=docker
export CLUSTER=docker                       # or set it once per shell
```

- **vm:** kubeconfig `vm/.state/kubeconfig`, written by `make -C vm tunnel`. The Kubernetes API is reached only through SSH.
- **docker:** a private single-context copy of the `docker-desktop` context in `.state/docker-desktop.kubeconfig`
  (mode 0600, gitignored), refreshed on every run.
- Add-ons are MicroK8s add-ons on vm. On docker they are the same upstream Helm charts at the same pinned versions:
  cert-manager v1.20.2, and Traefik chart 39.0.8 on a ClusterIP service with no dashboard.
- **kind:** `.state/kind.kubeconfig` from `kind get kubeconfig`. Cluster lifecycle is `make -C kind up/down`, see [`kind/README.md`](kind/README.md).
- Nothing is published on the Mac. Every docker URL goes through a `make tunnel` port-forward on `127.0.0.1`.
