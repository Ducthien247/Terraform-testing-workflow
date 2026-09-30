resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.address_space
  tags                = var.tags
}

# The stack used to be a VM template; these keep the existing state entries
# attached to the renamed resources instead of planning a destroy/create.
moved {
  from = azurerm_resource_group.vm
  to   = azurerm_resource_group.main
}

moved {
  from = azurerm_virtual_network.vm
  to   = azurerm_virtual_network.main
}

# ---------------------------------------------------------------------------
# Legacy VM stack cleanup — remove these blocks once the next apply succeeds.
#
# The resources below were deleted in Azure (soft-deleted in the case of the
# vault and its secret) but Terraform still has them in state. The purge step
# that normally follows a delete requires a permission the CI principal does
# not have (ForbiddenByPolicy), so `terraform destroy` cannot finish cleanly.
#
# `removed { lifecycle { destroy = false } }` tells Terraform to drop each
# entry from state WITHOUT attempting to destroy or purge anything in Azure.
# The soft-deleted vault and secret expire on their own after 7 days.
# ---------------------------------------------------------------------------

removed {
  from = azurerm_key_vault_secret.admin_password
  lifecycle { destroy = false }
}

removed {
  from = azurerm_key_vault.vm
  lifecycle { destroy = false }
}

removed {
  from = random_password.vm_admin
  lifecycle { destroy = false }
}
