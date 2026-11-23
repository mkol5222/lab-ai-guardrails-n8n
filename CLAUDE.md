# CLAUDE.md

Guidance for AI coding assistants (and humans) working on this lab repository.

## What this is

A hands-on training lab: an n8n AI agent whose LLM traffic goes only through a private LiteLLM gateway (`llmgw/`) guarded by
Check Point Lakera Guard. Everything is driven by `make` and installed with Helm charts.

| Folder | Role |
|---|---|
| `n8n/` | n8n Helm chart + Makefile, workflow JSON in `n8n/workflows/` |
| `llmgw/` | LiteLLM gateway chart: Lakera guardrails, Postgres sidecar, nginx TLS sidecar with route allowlist |
| `nginx/` | Small pod-name HTTPS demo (Traefik ingress) |
| `kind/`, `.devcontainer/` | kind cluster in Docker-in-Docker (local devcontainer and GitHub Codespaces) |
| `vm/` | Azure VM with MicroK8s (Terraform) |
| `common/` | `k8s.mk` (cluster selection, preflight), `ensure-addons.sh` (cert-manager, Traefik) |

Lab guides: `LAB-CODESPACES.md`, `LAB-DEVCONTAINER-LOCAL.md`, `LAB-GUIDE.md` (Docker Desktop).

## Clusters

Every app Makefile takes `CLUSTER=vm|docker|kind` (default `vm`; the devcontainer presets `kind`). A change must keep
**all three** working, so check each one with a dry run:

```bash
for c in vm docker kind; do for p in nginx n8n llmgw; do make -n -C $p up CLUSTER=$c >/dev/null || echo "FAIL $c/$p"; done; done
```

## Build and test

```bash
helm lint n8n/chart llmgw/chart nginx/chart
terraform -chdir=vm/terraform fmt -check && terraform -chdir=vm/terraform validate
bash -n */scripts/*.sh common/*.sh .devcontainer/*.sh
make -C n8n test; make -C llmgw test; make -C n8n llm-test     # against a running cluster
```

The tests print `PASS`, `FAIL` or `SKIP` lines. A `SKIP` must say why (for example a free-tier 429, or no public IP on this cluster type).

## Rules

- **Secrets:** never put keys in values, files, git, argv or output. Provider keys come from `make -C llmgw secrets`, which takes
  hidden input or Codespaces secrets. Generated keys come from in-cluster `lookup` templates. Scripts pass secrets through pipes,
  stdin or `-H @<(printf ...)`. Local state lives in gitignored `.state/` (0600/0700).
- **TLS:** never disable certificate verification (no `-k`, no `NODE_TLS_REJECT_UNAUTHORIZED=0`, no "Ignore SSL issues").
  Trust the private CA instead (`--cacert`, `NODE_EXTRA_CA_CERTS`). TLS 1.2+ only.
- **No public exposure:** ClusterIP services, port-forwards on `127.0.0.1`, private Codespaces ports. No NodePort or LoadBalancer, no
  host port mappings.
- **Guardrails:** LLM traffic goes only to guarded `/v1/chat/completions`, and the nginx allowlist returns 403 for everything else. New
  models get the Lakera policy binding; `unguarded/` stays opt-in for comparison demos only.
- **Supply chain:** pin image tags, chart versions and tool versions, and verify downloaded binaries with SHA-256 checksums.
- **Data:** synthetic lab prompts only.
- **Docs:** update the folder's `README.md` and `CHANGELOG.md` (Keep a Changelog) with every change, and the lab guides when
  commands change.
- **Public repo hygiene:** no personal emails, IPs, cloud subscription or tenant IDs, hostnames of real environments, or
  organization-internal policy names and URLs. Scan before pushing.
