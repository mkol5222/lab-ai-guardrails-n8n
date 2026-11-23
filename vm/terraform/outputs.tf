output "resource_group" { value = azurerm_resource_group.rg.name }
output "vm_name" { value = azurerm_linux_virtual_machine.vm.name }
output "vm_id" { value = azurerm_linux_virtual_machine.vm.virtual_machine_id }
output "vm_size" { value = azurerm_linux_virtual_machine.vm.size }
output "location" { value = azurerm_resource_group.rg.location }
output "public_ip" { value = azurerm_public_ip.pip.ip_address }
output "fqdn" { value = azurerm_public_ip.pip.fqdn }
output "admin_username" { value = var.admin_username }
output "allowed_cidrs" { value = var.allowed_cidrs }
output "spot" { value = var.spot }
output "image" { value = "Canonical:${var.image_offer}:${var.image_sku}:latest" }
output "microk8s_channel" { value = var.microk8s_channel }
output "auto_shutdown" { value = var.auto_shutdown_time == "" ? "disabled" : "${var.auto_shutdown_time} ${var.timezone}" }

# Console-only password (serial console / sudo); SSH stays key-only.
output "admin_password" {
  value     = random_password.admin.result
  sensitive = true
}
