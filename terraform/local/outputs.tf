# One output namespace per service (langfuse_*/grafana_*/prometheus_*).

output "langfuse_url" {
  value = "http://localhost:3000"
}

output "langfuse_login_email" {
  value = var.init_user_email
}

output "langfuse_login_password" {
  value     = random_password.init_user.result
  sensitive = true
}

output "langfuse_public_key" {
  value = "pk-lf-${random_id.project_public_key.hex}"
}

output "langfuse_secret_key" {
  value     = "sk-lf-${random_id.project_secret_key.hex}"
  sensitive = true
}

output "grafana_url" {
  value = local.grafana_url
}

output "grafana_login_user" {
  value = var.grafana_admin_user
}

output "grafana_login_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}

output "prometheus_url" {
  value = local.prometheus_url
}
