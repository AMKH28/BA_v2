output "node_ips" {
  value = { for k, m in module.rke2_nodes : k => m.ip }
}

output "node_roles" {
  value = { for k, v in var.cluster_nodes : k => v.role }
}
