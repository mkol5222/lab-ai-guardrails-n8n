# Changelog

All notable changes to `lab-ai-guardrails-n8n/vm`. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.0] - 2026-11-23

### Added
- NSG rule `https-from-operator`: TCP 443 from the same allowed CIDRs as SSH, for the ingress used by `../nginx`.

## [0.1.0] - 2026-11-23

### Added
- Terraform module (azurerm ~> 4.20) for an Ubuntu 26.04 LTS VM (Gen2, Trusted Launch) using `az login` auth.
- cloud-init first-boot setup: MicroK8s snap (configurable channel and addons), k9s from GitHub releases with
  checksum verification, jq, curl, kubeconfig, `kubectl`/`helm` aliases, bash completion.
- Makefile targets: `up`, `down`, `info`, `ssh`, `serial`, plus `pass`, `k9s`, `status`, `log`, `tunnel`, `wait`,
  `stop`, `start`, `allow`, `plan`.
- NSG limited to the operator's public IP /32. The Kubernetes API is reachable only through an SSH tunnel.
- Random console password for the serial console (only the bcrypt hash goes to the VM). SSH stays key-only.
- Daily auto-shutdown, subscription pinning, per-instance known_hosts.
