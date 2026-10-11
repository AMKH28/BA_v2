cluster_nodes = {
  "rke2-server-01" = {
    role   = "server"
    vmid   = 240
    cores  = 2
    memory = 4096
    disk   = 32
  }
  "rke2-agent-01" = {
    role   = "agent"
    vmid   = 241
    cores  = 2
    memory = 3072
    disk   = 32
  }
  "rke2-agent-02" = {
    role   = "agent"
    vmid   = 242
    cores  = 2
    memory = 3072
    disk   = 32
  }
  "rke2-storage-01" = {
    role   = "storage"
    vmid   = 243
    cores  = 2
    memory = 2048
    disk   = 64
  }
}
