output "grafana_admin_username" {
  value = local.grafana_admin_username
}

output "grafana_admin_password" {
  value     = local.grafana_admin_password
  sensitive = true
}