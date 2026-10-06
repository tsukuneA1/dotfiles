# Not a secret, safe to commit (password is generated separately via
# random_password.grafana_admin).

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}
