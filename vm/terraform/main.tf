resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# Console password for the admin user: used only for the Azure serial console login.
# SSH stays key-only (sshd password auth disabled). Only the bcrypt hash goes to the VM;
# the clear text lives in local terraform state (gitignored) and `make pass`.
resource "random_password" "admin" {
  length           = 24
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "-_.!%+="
}

locals {
  name = "${var.name}-${random_string.suffix.result}"
  tags = merge({ app = "lab-ai-guardrails-n8n", managed-by = "terraform" }, var.tags)

  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    admin_username   = var.admin_username
    password_hash    = random_password.admin.bcrypt_hash
    microk8s_channel = var.microk8s_channel
    microk8s_addons  = join(" ", var.microk8s_addons)
    k9s_version      = var.k9s_version
  })
}

resource "azurerm_resource_group" "rg" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags

  lifecycle {
    # Cloud governance policies may stamp extra tags; ignore them to keep plans clean.
    ignore_changes = [tags]
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.43.0.0/24"]
  tags                = local.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_subnet" "vm" {
  name                 = "vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.43.0.0/26"]
}

resource "azurerm_public_ip" "pip" {
  name                = "${local.name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.name
  tags                = local.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# Inbound SSH + HTTPS only from the operator's current public IP (refreshed by make up/start/allow).
# The Kubernetes API (16443) is not exposed; use `make tunnel` for local kubectl.
resource "azurerm_network_security_group" "nsg" {
  name                = "${local.name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  security_rule {
    name                       = "ssh-from-operator"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_cidrs
    destination_address_prefix = "*"
  }

  # HTTPS to the MicroK8s ingress (Traefik hostPort 443), same operator-only sources.
  security_rule {
    name                       = "https-from-operator"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.allowed_cidrs
    destination_address_prefix = "*"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "${local.name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_network_interface_security_group_association" "nic" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${local.name}-vm"
  computer_name         = local.name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic.id]

  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = trimspace(file(var.ssh_public_key_path))
  }

  # Changing cloud-init (or anything it templates) rebuilds the VM: it only runs at first boot.
  custom_data = base64encode(local.cloud_init)

  priority        = var.spot ? "Spot" : "Regular"
  eviction_policy = var.spot ? "Deallocate" : null
  max_bid_price   = var.spot ? -1 : null

  # Trusted Launch
  secure_boot_enabled = true
  vtpm_enabled        = true

  os_disk {
    name                 = "${local.name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
    # Managed disks are encrypted at rest with platform-managed AES-256 keys by default.
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = var.image_offer
    sku       = var.image_sku
    version   = "latest"
  }

  boot_diagnostics {} # managed storage: enables `make serial` and `make log`

  tags = local.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "autostop" {
  count                 = var.auto_shutdown_time == "" ? 0 : 1
  virtual_machine_id    = azurerm_linux_virtual_machine.vm.id
  location              = azurerm_resource_group.rg.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.timezone

  notification_settings {
    enabled = false
  }
  tags = local.tags

  lifecycle {
    ignore_changes = [tags]
  }
}
