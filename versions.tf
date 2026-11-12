terraform {
  required_providers {
    cato = {
      source = "catonetworks/cato"
      # version = ">= 0.0.5"
      version = ">= 1.5.0-prerelease.3"
    }
  }
  required_version = ">= 1.13"
}