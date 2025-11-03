terraform {
  required_providers {
    cato = {
      # source = "catonetworks/cato"
      # version = ">= 0.0.51"
      source  = "terraform-providers/cato"
      version = "0.0.51"
    }
  }
  required_version = ">= 1.13"
}