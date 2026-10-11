resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  vm_id     = var.vmid
  node_name = var.node_name

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  agent {
    enabled = true
    timeout = "5m" # Terraform wartet, bis der Agent eine IP meldet
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk
  }

  network_device {
    bridge = var.bridge # MAC vergibt Proxmox selbst
  }

  initialization {
    #datastore_id = var.datastore_id
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      username = "ubuntu"
      keys     = [trimspace(file("~/.ssh/id_ed25519.pub"))]
    }
  }
}
