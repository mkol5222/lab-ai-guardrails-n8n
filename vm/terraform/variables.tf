variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "mk8s"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "vm_size" {
  description = "VM size. D4as_v5 = 4 vCPU AMD / 16 GiB, non-burstable; comfortable for MicroK8s plus a few workloads."
  type        = string
  default     = "Standard_D4as_v5"
}

variable "spot" {
  description = "Run as Spot VM (much cheaper, may be evicted -> deallocated)."
  type        = bool
  default     = false
}

variable "os_disk_type" {
  description = "StandardSSD_LRS (economical) or Premium_LRS (faster)."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB (container images and hostpath volumes live here)."
  type        = number
  default     = 64
}

variable "image_offer" {
  description = "Canonical image offer."
  type        = string
  default     = "ubuntu-26_04-lts"
}

variable "image_sku" {
  description = "Canonical image SKU (server = Gen2 x64; server-arm64 needs an ARM size such as Standard_D4ps_v5)."
  type        = string
  default     = "server"
}

variable "admin_username" {
  description = "Admin (sudo) user on the VM."
  type        = string
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.admin_username)) && !contains(["admin", "administrator", "root", "user", "guest", "test", "ubuntu"], var.admin_username)
    error_message = "admin_username must be a lowercase Linux user name and not a reserved name (admin, root, ubuntu, ...)."
  }
}

variable "ssh_public_key_path" {
  description = "SSH public key authorized for admin_username (the Makefile generates one in .state/)."
  type        = string
}

variable "allowed_cidrs" {
  description = "Source CIDRs allowed to reach SSH and HTTPS. The Makefile sets this to your current public IP /32."
  type        = list(string)
  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0)) && !contains(["0.0.0.0/0", "::/0", "*", "Internet", "Any"], c) && tonumber(split("/", c)[1]) >= 16])
    error_message = "allowed_cidrs must be specific prefixes (/16 or narrower). Opening SSH/HTTPS to 0.0.0.0/0 is not allowed (keep management ports closed to the Internet)."
  }
}

variable "microk8s_channel" {
  description = "MicroK8s snap channel, e.g. latest/stable or 1.35/stable."
  type        = string
  default     = "latest/stable"
}

variable "microk8s_addons" {
  description = "MicroK8s addons enabled at first boot."
  type        = list(string)
  default     = ["dns", "hostpath-storage"]
}

variable "k9s_version" {
  description = "k9s release tag (e.g. v0.51.0) or \"latest\". The download is verified against the release's checksums.sha256."
  type        = string
  default     = "latest"
}

variable "timezone" {
  description = "Time zone for the auto-shutdown schedule (Windows time zone id, as Azure expects)."
  type        = string
  default     = "Central Europe Standard Time"
}

variable "auto_shutdown_time" {
  description = "Daily auto-deallocate time (HHMM, in var.timezone). Empty string disables it."
  type        = string
  default     = "2000"
}

variable "tags" {
  type    = map(string)
  default = {}
}
