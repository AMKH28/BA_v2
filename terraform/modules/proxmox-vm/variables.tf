variable "name" { type = string }
variable "vmid" { type = number }
variable "cores" { type = number }
variable "memory" { type = number } # in MB
variable "disk" { type = number }   # in GB
variable "role" { type = string }

variable "template_vmid" {
  description = "VM-ID des Templates mit QEMU Guest Agent, von dem geklont wird"
  type        = number
  default     = 9000
}

variable "node_name" {
  type    = string
  default = "pve-lab"
}

variable "datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "bridge" {
  type    = string
  default = "vmbr1"
}
