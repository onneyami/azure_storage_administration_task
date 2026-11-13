variable "location" {
  type        = string
  default     = "northeurope"
  description = "Target location for resources"
}

variable "rg_name" {
  type        = string
  default     = "rg-andrei"
  description = "The name of target resource group"
}