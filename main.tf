# Provider
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.16.0"
    }
  }
}
provider "azurerm" {
  # Configuration options
  features {}
  subscription_id = "c23a3174-f9e7-4414-9f75-966ddbb786fb"
}

module "module1" {
source = "./modules/vm_module"
instance_size = var.instance_size
location = var.location
tags = var.tags 
}