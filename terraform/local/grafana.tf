# Grafana's docker-compose.yml/.env live in ../../services/grafana, not
# here. Admin password: same random-generation approach as langfuse.tf.

locals {
  grafana_dir = "${path.module}/../../services/grafana"
  grafana_url = "http://localhost:3001"
}

resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "local_sensitive_file" "grafana_env" {
  filename        = "${local.grafana_dir}/.env"
  file_permission = "0600"

  content = <<-EOT
    GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}
    GF_SECURITY_ADMIN_PASSWORD=${random_password.grafana_admin.result}
  EOT
}

# Same lifecycle pattern as langfuse.tf. `--wait` blocks until Grafana's
# API is reachable, so later grafana provider resources can rely on it.
resource "terraform_data" "grafana_compose_up" {
  triggers_replace = {
    env_sha256     = local_sensitive_file.grafana_env.content_sha256
    compose_sha256 = filesha256("${local.grafana_dir}/docker-compose.yml")
    # destroy-time provisioners can only read `self`, not top-level locals.
    grafana_dir = local.grafana_dir
  }

  provisioner "local-exec" {
    working_dir = local.grafana_dir
    command     = "docker compose --parallel 1 up -d --wait --wait-timeout 300"
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers_replace.grafana_dir
    command     = "docker compose down"
  }

  depends_on = [local_sensitive_file.grafana_env, terraform_data.network]
}

# Basic auth, not a token: grafana_user (cross-org user management) doesn't
# support API key/service account auth.
provider "grafana" {
  url  = local.grafana_url
  auth = "${var.grafana_admin_user}:${random_password.grafana_admin.result}"
}

resource "grafana_folder" "local" {
  title = "Local"

  depends_on = [terraform_data.grafana_compose_up]
}

# Built-in TestData source, used by the sample "Welcome" dashboard below.
# Real data sources: prometheus.tf / langfuse_grafana.tf.
resource "grafana_data_source" "testdata" {
  type = "grafana-testdata-datasource"
  name = "TestData"

  depends_on = [terraform_data.grafana_compose_up]
}

# Sample dashboard proving Terraform management works; just shows
# TestData's random_walk scenario.
resource "grafana_dashboard" "welcome" {
  folder = grafana_folder.local.uid

  config_json = jsonencode({
    title         = "Welcome"
    uid           = "local-welcome"
    schemaVersion = 39
    panels = [
      {
        id    = 1
        title = "Random Walk (TestData)"
        type  = "timeseries"
        datasource = {
          type = "grafana-testdata-datasource"
          uid  = grafana_data_source.testdata.uid
        }
        targets = [
          {
            scenarioId = "random_walk"
            refId      = "A"
          }
        ]
        gridPos = { h = 8, w = 24, x = 0, y = 0 }
      }
    ]
  })

  depends_on = [terraform_data.grafana_compose_up]
}
