# nginx — pod-name web server on the MicroK8s VM, over HTTPS

A Helm chart (`chart/`) driven by `make`. It deploys an nginx web server whose homepage shows **the name of the pod that
served the request**, published at `https://<vm-fqdn>/` through the MicroK8s Traefik ingress. TLS uses a
**cert-manager self-signed CA**, so no ACME and no inbound port 80 are needed.

It deploys through the `make tunnel` session of [`../vm`](../vm), using kubeconfig `../vm/.state/kubeconfig`.

## Quick start

```bash
make -C ../vm up                 # VM (once)
make -C ../vm tunnel             # terminal 1: keep it open
make up                          # terminal 2: deploy, wait, print the URL
make test                        # verify
make down                        # remove the release + namespace
```

You need `helm` (`brew install helm`), `kubectl`, `jq`, `openssl` and `terraform`. `make up` uses terraform to read the VM's FQDN.

## Clusters

| | `CLUSTER=vm` (default) | `CLUSTER=docker` |
|---|---|---|
| Cluster | MicroK8s on the [`../vm`](../vm) Azure VM, through `make -C ../vm tunnel` | Docker Desktop Kubernetes (context `docker-desktop`) |
| Add-ons | MicroK8s `ingress` (Traefik) + `cert-manager` | the same Helm charts and versions (Traefik 39.0.8 with a ClusterIP service and no dashboard, cert-manager v1.20.2) |
| URL | `https://<vm-fqdn>/`, open only to your IP through the NSG | `https://web.localhost:9443/` through `make tunnel CLUSTER=docker` |
| `make test` | direct to the FQDN, and port 80 must be closed | temporary port-forward to Traefik, and Traefik must not be published on the Mac |

```bash
make up CLUSTER=docker && make test CLUSTER=docker
make tunnel CLUSTER=docker          # keep open, browse https://web.localhost:9443/
export CLUSTER=docker               # or set it for the whole shell
```

State (the exported CA) is kept per cluster in `.state/<cluster>/`.

## Targets

| Target | What it does |
|---|---|
| `make up` | Enables the MicroK8s `ingress` and `cert-manager` addons if they are missing, points the NSG at your current IP, runs `helm upgrade --install`, waits for the pods and certificate, exports the CA and prints `info` |
| `make down` | Uninstalls the release and deletes the namespace. The addons and the VM stay |
| `make info` | URL, release revision, certificate expiry and renewal, pods |
| `make test` | 12 HTTPS requests **verified against the exported CA** (no `-k`). Checks that each page shows a running pod's name, that the server rejects TLS 1.1, and that port 80 is closed |
| `make ca` | Exports the CA to `.state/<cluster>/ca.crt` |

Variables: `NS=web`, `RELEASE=web`, and `HELM_ARGS="--set replicaCount=3"` for chart values.

## How it works

```
Mac ──https (your IP only, NSG)──▶ VM:443 Traefik (hostPort, ingress addon) ──▶ Service web ──▶ nginx pods (2)
Mac ──make tunnel (SSH) ─────────▶ VM:16443 Kubernetes API  (helm / kubectl)
```

- **Page:** nginx returns HTML that contains `$hostname`, which is the pod name. The image is `nginxinc/nginx-unprivileged`, running non-root with a read-only root filesystem and all capabilities dropped. `/pod` returns the pod name as plain text, `/healthz` is the health probe, and the `X-Pod-Name` header carries the name too.
- **TLS:** a cert-manager `selfSigned` Issuer bootstraps a private CA (ECDSA P-256, 10 years). A CA Issuer signs the host certificate (90 days, rotated automatically 15 days before expiry). Traefik accepts only TLS 1.2 and 1.3.
- **Exposure:** the Ingress is bound to Traefik's `websecure` entrypoint only. The NSG opens 443 to the same operator CIDRs as SSH, and **port 80 is never opened**. A NetworkPolicy allows traffic to the pods only from the `ingress` namespace.

## Trusting the CA

Browsers warn until you trust the CA. For a single command, pass it explicitly:

```bash
curl --cacert .state/<cluster>/ca.crt https://<vm-fqdn>/
```

To trust it system-wide on macOS (remove it later in Keychain Access):

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain .state/<cluster>/ca.crt
```

`make down` deletes the CA. The next `make up` creates a new one, so trust the new `.state/<cluster>/ca.crt` again.

## Why not Let's Encrypt?

An ACME HTTP-01 (or TLS-ALPN-01) challenge needs the VM reachable from the whole Internet. This setup only admits your
IP, which is the point of this lab: no admin or app ports open to the Internet. If you need a publicly trusted certificate, use DNS-01 with a DNS zone you control.
That needs no inbound access, but it does need a DNS API token stored as a Kubernetes Secret.

## Troubleshooting

- **`Cluster not reachable`:** start `make -C ../vm tunnel` in another terminal.
- **The HTTPS request times out:** your IP changed. `make up` (or `make -C ../vm allow`) updates the NSG.
- **Certificate not Ready:** run `kubectl -n web describe certificate web-tls` and `kubectl -n cert-manager logs deploy/cert-manager`.
