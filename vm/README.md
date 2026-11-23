# vm — Ubuntu 26.04 LTS + MicroK8s on Azure

One `make up` gives you an Azure VM running **Ubuntu 26.04 LTS** with **MicroK8s**, **k9s**, **jq** and **curl**
preinstalled, plus a kubeconfig ready for your admin user. Terraform runs on your Mac and signs in with your
`az login` session. There are no service principals and no secrets in files.

## Prerequisites (macOS)

```bash
brew install azure-cli terraform
az login                     # pick the subscription: az account set -s <name|id>
```

`make serial` installs the `serial-console` az extension the first time you run it.

## Quick start

```bash
cd vm
make up        # create VM, wait until MicroK8s is ready, print info   (~5-8 min)
make ssh       # shell on the VM: kubectl / k / helm / k9s just work
make k9s       # straight into k9s
make down      # destroy everything
```

## Targets

| Target | What it does |
|---|---|
| `make up` | Create or update the VM (idempotent), wait for first-boot setup, show `info` |
| `make down` | Destroy the resource group and everything in it (`FORCE=1` skips the prompt) |
| `make info` | Name, size, image, power state, IP/FQDN, user, allowed CIDRs, auto-shutdown |
| `make ssh` | SSH in as your user. `make ssh CMD="kubectl get pods -A"` runs a single command |
| `make serial` | Interactive Azure serial console. Log in with the password from `make pass`. Leave with `Ctrl+]` then `q` |
| `make pass` | Copy the console password to the clipboard |
| `make k9s` | Run k9s on the VM |
| `make status` | Provisioning result, OS/tool versions, nodes and pods |
| `make log` | Serial boot log from boot diagnostics (works when SSH doesn't; `N=200` for more lines) |
| `make tunnel` | Use kubectl/k9s **from your Mac**: writes `.state/kubeconfig` and forwards the API over SSH |
| `make stop` / `make start` | Deallocate (no compute billing) / start again and refresh the NSG with your IP |
| `make allow` | Point the SSH/HTTPS rules at your current public IP (after a network change) |
| `make plan` | Show what `up` would change |
| `make wait` | Wait for SSH and cloud-init (part of `up`) |

## What gets built

- Resource group `mk8s-<random>-rg` with a VNet, an NSG, a static public IP with a DNS label, a NIC and the VM
- Image `Canonical:ubuntu-26_04-lts:server:latest` (Gen2), Trusted Launch (Secure Boot and vTPM), `Standard_D4as_v5` with 4 vCPU and 16 GiB
- A 64 GiB StandardSSD OS disk, encrypted at rest with platform-managed keys
- First-boot setup through cloud-init (`terraform/cloud-init.yaml.tftpl`):
  - `apt`: jq, curl, ca-certificates, bash-completion, and a full package upgrade
  - The `microk8s` snap (channel `latest/stable`) with the `dns` and `hostpath-storage` addons. Your user joins the `microk8s` group
  - `kubectl` and `helm` snap aliases, `~/.kube/config`, kubectl bash completion, and an alias `k`
  - `k9s` from the official GitHub release, **checked against the release's `checksums.sha256`** before it is installed
  - Log in `/var/log/mk8s-setup.log`, result in `/var/lib/mk8s-setup/status.json`
- A daily auto-deallocate at 20:00 Central Europe time

## Security model

- **SSH is key-only.** The Makefile generates a private ed25519 key in `.state/`. Password login over SSH is disabled.
- **The NSG allows only your current public IP /32** on ports 22 (SSH) and 443 (HTTPS to the ingress, see `../nginx`), plus any `EXTRA_CIDRS`. `0.0.0.0/0` and anything wider
  than /16 are rejected by variable validation.
- **The Kubernetes API (16443) is never exposed.** Use `make tunnel` (SSH port forward to 127.0.0.1).
- **The console password** works only on the serial console. It is random, and only its bcrypt hash goes to the VM. The clear text
  lives in the local terraform state (gitignored) and reaches you through `make pass`.
- SSH host keys are trust-on-first-use and kept in `.state/known_hosts`. They reset automatically when the VM is rebuilt.
- The subscription is pinned at the first `make up` (`.state/subscription`), so a later `az account set` can't send
  `down` to the wrong subscription.

## Customizing

Pass make variables, or export `TF_VAR_*` for any variable in `terraform/variables.tf`:

```bash
make up VM_USER=alice EXTRA_CIDRS="203.0.113.0/24"
TF_VAR_vm_size=Standard_D8as_v5 TF_VAR_location=northeurope make up
TF_VAR_microk8s_channel=1.35/stable TF_VAR_microk8s_addons='["dns","hostpath-storage","ingress","metrics-server"]' make up
TF_VAR_spot=true make up                 # much cheaper, may be evicted
TF_VAR_auto_shutdown_time="" make up     # disable auto-shutdown
TF_VAR_k9s_version=v0.51.0 make up       # pin k9s
```

Keep the same `TF_VAR_*` values on later `up` and `plan` runs, or put them in `terraform/terraform.tfvars`, which is gitignored.

> cloud-init runs only at first boot. Changing the template, channel, addons or k9s version **rebuilds the VM**,
> and `terraform plan` shows it as a replace. Size, NSG and auto-shutdown changes are applied in place.

## Local kubectl via tunnel

```bash
make tunnel                                   # terminal 1, stays open
export KUBECONFIG=$PWD/.state/kubeconfig      # terminal 2
kubectl get nodes; k9s
```

## Troubleshooting

- **SSH times out:** your IP changed. Run `make allow`. If the VM was stopped, run `make start`.
- **Setup failed:** run `make status`, or `make ssh CMD="sudo tail -100 /var/log/mk8s-setup.log"`.
- **No SSH at all:** run `make log` for the boot output, or `make serial` and log in with `make pass`.
- **Serial console says it is disabled:** a subscription admin has to enable it (`az serial-console enable`).

## Cost

Compute bills only while the VM runs (D4as_v5 is about $0.17/h in West Europe). The disk and static IP bill until `make down`.
