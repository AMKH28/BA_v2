output "ip" {
  description = "Erste IPv4-Adresse außer Loopback, vom QEMU Guest Agent gemeldet"
  value = try(
    flatten([
      for i, ifname in proxmox_virtual_environment_vm.this.network_interface_names :
      proxmox_virtual_environment_vm.this.ipv4_addresses[i] if ifname != "lo"
    ])[0],
    null
  )
}
