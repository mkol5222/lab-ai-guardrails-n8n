# n8n — private self-hosted n8n on the MicroK8s VM

A Helm chart (`chart/`) driven by `make`, in the same style as [`../nginx`](../nginx). It runs a single n8n instance
(SQLite on a persistent volume) that serves **HTTPS itself**, using a certificate from a **cert-manager private CA**.

n8n is **not exposed outside the cluster**. There is no Ingress, no NodePort and no LoadBalancer, only a ClusterIP Service.
You reach it at **https://n8n.localhost:8443/** through `make tunnel`, which is a `kubectl port-forward` running inside
the `../vm` SSH tunnel. That tunnel is key-only and limited to your IP.

## Quick start

```bash
make -C ../vm up                  # VM (once)
make -C ../vm tunnel              # terminal 1: Kubernetes API tunnel, keep open
make up                           # terminal 2: deploy n8n, wait until ready, print info
make tunnel                       # terminal 2: keep open -> browse https://n8n.localhost:8443/
make test                         # terminal 3: verify
```

On your first visit, n8n shows its setup screen. Create the owner account there.

## Clusters

| | `CLUSTER=vm` (default) | `CLUSTER=docker` |
|---|---|---|
| Cluster | MicroK8s on [`../vm`](../vm), through `make -C ../vm tunnel` | Docker Desktop Kubernetes (context `docker-desktop`) |
| cert-manager | MicroK8s addon | Helm chart v1.20.2 (the same version the addon uses) |
| URL | `https://n8n.localhost:8443/` through `make tunnel` | the same, through `make tunnel CLUSTER=docker` |
| `make test` | including the probe that the VM's public IP doesn't serve n8n | the public-IP probe is skipped |

```bash
make up CLUSTER=docker && make test CLUSTER=docker && make tunnel CLUSTER=docker
```

Each cluster keeps its own data (PVC + encryption key, inside that cluster), and the exported CA goes to `.state/<cluster>/`.
Docker Desktop's storage class is used automatically. Whether NetworkPolicy is enforced depends on Docker Desktop's CNI, and the
kind-mode kindnet version may not enforce it. Docker Desktop publishes nothing on the Mac either way: the Service is
ClusterIP and there is no Ingress.

## Targets

| Target | What it does |
|---|---|
| `make up` | Enables the cert-manager addon if it is missing, runs `helm upgrade --install --wait`, waits for the certificate, restarts n8n if the certificate was renewed, exports the CA and prints `info` |
| `make down` | Uninstalls the release. **Keeps** the data PVC and the encryption key, so the next `make up` brings back your workflows and credentials. `PURGE=1` deletes the namespace and everything in it |
| `make info` | URL, chart and app version, certificate SANs and expiry, PVC, exposure, pod |
| `make test` | Uses its own temporary port-forward on port 18443. Checks `/healthz` and the editor UI over HTTPS **verified against the private CA**. Checks that the server rejects TLS 1.1, that the namespace has no Ingress, IngressRoute, HTTPRoute, NodePort or LoadBalancer, and that the VM's public IP does not present n8n's certificate |
| `make tunnel` | `kubectl port-forward` on `127.0.0.1:8443` to the n8n Service |
| `make ca` | Exports the CA to `.state/<cluster>/ca.crt` |
| `make llm-connect` | Connects n8n to `../llmgw`: copies the CA, creates the credential (scoped key), imports `WORKFLOW` and restarts n8n |
| `make llm-test` | Runs from **inside the n8n pod**: verified TLS, key scope, a benign prompt answered, the injection blocked by Lakera, `/v1/responses` refused, the key unable to mint keys, and a NetworkPolicy probe from another namespace |

Variables: `PORT=8443`, `N8N_HOST=n8n.localhost`, `NS=n8n`, `RELEASE=n8n`, and `HELM_ARGS="--set extraEnv.N8N_LOG_LEVEL=debug"`.
If you change `PORT` or `N8N_HOST`, run `make up` again, because n8n renders its URL from them.

## Using the in-cluster LLM gateway (llmgw)

n8n's AI nodes can use [`../llmgw`](../llmgw), the LiteLLM gateway with Check Point Lakera Guard, without leaving the
cluster. The workflow [`workflows/llmgw-chat-agent.json`](workflows/llmgw-chat-agent.json) is a reusable Chat Trigger, AI Agent
and OpenAI Chat Model setup.

```bash
make -C ../llmgw up CLUSTER=docker                     # gateway (with Postgres for scoped keys)
make -C ../llmgw client-key CLIENT=n8n CLUSTER=docker  # scoped key -> secret llmgw/llmgw-client-n8n
make llm-connect CLUSTER=docker                        # CA trust + credential + workflow import, restarts n8n
make llm-test CLUSTER=docker                           # tests from inside the n8n pod
```

| Setting | Value |
|---|---|
| Credential | **OpenAI API** type, named `llmgw (Lakera-guarded)` (id `LlmgwGuardedKey1`), created by `make llm-connect` |
| Base URL | `https://llmgw.llmgw.svc.cluster.local/v1` (the in-cluster Service name, covered by the llmgw certificate) |
| API key | scoped LiteLLM virtual key: Lakera-blocking models only, 30 requests/min, no admin rights. Never the master key |
| TLS | n8n trusts the llmgw private CA through `NODE_EXTRA_CA_CERTS` (ConfigMap `llmgw-ca`). **Never** turn on "Ignore SSL issues" |
| Model | `google/gemma-4-31b-it:free`: tool calling and JSON output, 262k context, stable results. If it is rate-limited (429), llmgw falls back to `openrouter/free` automatically, still Lakera-guarded. Avoid the `nvidia/nemotron-3*` models for structured output |
| **Use Responses API** | **off**. Lakera only guards Chat Completions, and the gateway returns 403 for `/v1/responses` anyway |

The model dropdown lists only what the key allows. The plain model names are the ones where Lakera blocks flagged requests;
the `monitor/` and `unguarded/` variants are not available to n8n.

To reuse the workflow somewhere else, import the JSON (UI: *Import from File*, or `make llm-connect WORKFLOW=...`). It
contains no secrets, only a reference to the credential by ID and name.

**Scope:** this is a closed partner-training lab that runs outside Check Point's environment. It handles only
synthetic lab data, with no Check Point or customer data, so n8n and OpenRouter never see real data. If you reuse the
setup with real data, point llmgw at an approved enterprise endpoint, such as Azure OpenAI or AWS Bedrock, and get the
n8n/AI approvals first. The n8n side stays the same.

## Trusting the CA

```bash
curl --cacert .state/<cluster>/ca.crt https://n8n.localhost:8443/healthz
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain .state/<cluster>/ca.crt   # browsers
```

The certificate covers `n8n.localhost`, `localhost` and `127.0.0.1`. `*.localhost` resolves to loopback in browsers and curl.
`make down PURGE=1` deletes the CA, and the next `make up` creates a new one.

## Security notes

These follow common hardening practice for self-hosted automation platforms: private network access only, encrypted credentials, TLS everywhere, and least privilege.

- **No public exposure:** the only way in is your SSH tunnel to the VM. The NSG allows only your IP, on SSH and HTTPS. The
  HTTPS port belongs to the `../nginx` demo, and Traefik has no route to n8n. A NetworkPolicy denies all in-cluster traffic to the pod.
- **TLS:** n8n terminates TLS 1.2 or 1.3 with an ECDSA P-256 certificate (1 year, rotated by cert-manager; `make up` restarts
  n8n to load a renewed one). Cookies are `Secure`.
- **Credentials:** n8n encrypts stored credentials with `N8N_ENCRYPTION_KEY`. The chart generates that key once **inside the
  cluster**, keeps it in a Secret (reused on upgrade and kept on uninstall), and never writes it to values, files or git.
  Store credentials in n8n's credential store, never in workflow nodes or parameters.
- **Hardening:** non-root (uid 1000), no privilege escalation, all capabilities dropped, no service-account token,
  task runners enabled, `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`.
- **Data stays in-house:** telemetry, version checks, personalization, community packages and the built-in AI assistant
  are disabled.
- **Integrations:** call only approved enterprise endpoints from workflows. **Do not connect AI/LLM services**
  (Claude, OpenAI, and others) unless they have been approved through the security and legal review. To request an exception,
  go through that review process.

## Backup

```bash
kubectl -n n8n exec deploy/n8n -- n8n export:workflow --all --output=/home/node/.n8n/backup.json
kubectl -n n8n cp "$(kubectl -n n8n get pod -l app.kubernetes.io/instance=n8n -o name | cut -d/ -f2)":/home/node/.n8n/backup.json ./backup.json
```

Credentials exported with `export:credentials` stay encrypted with the instance key. Store such exports encrypted, never in git.

## Troubleshooting

- **`Cluster not reachable`:** start `make -C ../vm tunnel`.
- **The browser can't connect:** `make tunnel` isn't running, or the pod restarted. Restart `make tunnel`.
- **The pod isn't ready:** run `kubectl -n n8n logs deploy/n8n` and `kubectl -n n8n describe pod`.
