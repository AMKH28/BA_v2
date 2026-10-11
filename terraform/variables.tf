variable "proxmox_api_token" {
  description = "Proxmox API Token im Format user@realm!tokenname=secret"
  type        = string
  sensitive   = true
}

variable "cluster_nodes" {
  description = "Generische, providerunabhängige Cluster-Node-Definition"
  type = map(object({
    role   = string # "server", "agent" oder "storage"
    vmid   = number
    cores  = number
    memory = number # in MB
    disk   = number # in GB
  }))
}
