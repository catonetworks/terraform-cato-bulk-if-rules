terraform {
  required_providers {
    cato = {
      source = "catonetworks/cato"
      # version = ">= 0.0.5"
      version = ">= 1.2.0"
    }
  }
  required_version = ">= 1.13"
}