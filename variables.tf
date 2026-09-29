variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID or Azure CLI context."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group. Must match the RESOURCE_GROUP_NAME Actions variable so the lock steps target the right group."
  type        = string
  default     = "rg-terraform-vnet"
}

variable "vnet_name" {
  description = "Name of the virtual network."
  type        = string
  default     = "vnet-terraform"
}

variable "address_space" {
  description = "Address space of the virtual network."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "tags" {
  description = "Tags applied to the resource group and the virtual network."
  type        = map(string)
  default     = { managed_by = "terraform" }
}
