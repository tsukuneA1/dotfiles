# Prometheus's docker-compose.yml/prometheus.yml live in
# ../../services/prometheus. No secrets in the scrape config, so unlike
# langfuse/grafana there's no .env generation step here.

locals {
  prometheus_dir = "${path.module}/../../services/prometheus"
  # 9095: 9090 is already used by langfuse's minio.
  prometheus_url = "http://localhost:9095"
}

# Same lifecycle pattern as langfuse.tf/grafana.tf.
resource "terraform_data" "prometheus_compose_up" {
  depends_on = [terraform_data.network]
  triggers_replace = {
    compose_sha256    = filesha256("${local.prometheus_dir}/docker-compose.yml")
    prometheus_sha256 = filesha256("${local.prometheus_dir}/prometheus.yml")
    # destroy-time provisioners can only read `self`, not top-level locals.
    prometheus_dir = local.prometheus_dir
  }

  provisioner "local-exec" {
    working_dir = local.prometheus_dir
    command     = "docker compose --parallel 1 up -d --wait --wait-timeout 300"
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers_replace.prometheus_dir
    command     = "docker compose down"
  }
}

# Reached through container DNS on the shared local Docker network.
resource "grafana_data_source" "prometheus" {
  type = "prometheus"
  name = "Prometheus"
  url  = "http://prometheus:9090"

  json_data_encoded = jsonencode({
    httpMethod = "POST"
  })

  depends_on = [
    terraform_data.grafana_compose_up,
    terraform_data.prometheus_compose_up,
  ]
}
