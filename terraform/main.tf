terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.0.43:8006"
  api_token = var.proxmox_api_token
  insecure  = true
}

module "rke2_nodes" {
  source   = "./modules/proxmox-vm"
  for_each = var.cluster_nodes

  name   = each.key
  vmid   = each.value.vmid
  cores  = each.value.cores
  memory = each.value.memory
  disk   = each.value.disk
  role   = each.value.role
}
