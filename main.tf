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
