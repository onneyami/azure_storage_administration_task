terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.5"
    }
    random = {
      source  = "hashicorp/time"
      version = "~> 0.9.0"
    }
  }
}

provider "azurerm" {
  features {}
}

