terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox" # Muss hier im Modul WIEDERHOLT werden — Terraform vererbt required_providers nicht automatisch an Kind-Module
      version = "~> 0.66"     # Gleiche Version wie im Root-main.tf, damit keine Versionskonflikte entstehen
    }
  }
}
