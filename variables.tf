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
  description = "Name of the resource group. The lock workflow reads this out of the plan, so it needs no separate CI variable."
  type        = string
  default     = "rg-terraform-vm"
}

variable "vnet_name" {
  description = "Name of the virtual network."
  type        = string
  default     = "vm-terraform-linux-vnet"
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
