locals {
  telemetry_dir = "${path.module}/../../services/telemetry"
}

resource "local_sensitive_file" "telemetry_env" {
  filename        = "${local.telemetry_dir}/.env"
  file_permission = "0600"
  content         = "LANGFUSE_AUTH=${base64encode("pk-lf-${random_id.project_public_key.hex}:sk-lf-${random_id.project_secret_key.hex}")}\n"
}

resource "terraform_data" "telemetry_compose_up" {
  triggers_replace = {
    telemetry_dir    = local.telemetry_dir
    env_sha256       = local_sensitive_file.telemetry_env.content_sha256
    compose_sha256   = filesha256("${local.telemetry_dir}/docker-compose.yml")
    collector_sha256 = filesha256("${local.telemetry_dir}/collector.yml")
    loki_sha256      = filesha256("${local.telemetry_dir}/loki.yml")
  }
  provisioner "local-exec" {
    working_dir = local.telemetry_dir
    command     = "docker compose --parallel 1 up -d --wait --wait-timeout 300"
  }
  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers_replace.telemetry_dir
    command     = "docker compose down"
  }
  depends_on = [local_sensitive_file.telemetry_env, terraform_data.network,
  terraform_data.compose_up, terraform_data.prometheus_compose_up]
}

resource "grafana_data_source" "agent_logs" {
  type       = "loki"
  name       = "Agent Logs"
  uid        = "agent-logs"
  url        = "http://loki:3100"
  depends_on = [terraform_data.grafana_compose_up, terraform_data.telemetry_compose_up]
}

locals {
  prom_ds = { type = "prometheus", uid = grafana_data_source.prometheus.uid }
}

resource "grafana_dashboard" "agent_logs" {
  folder = grafana_folder.local.uid
  config_json = jsonencode({
    title         = "Agent Execution Logs"
    uid           = "agent-execution-logs"
    schemaVersion = 39
    time          = { from = "now-1h", to = "now" }
    refresh       = "10s"
    panels = [{
      id         = 1
      title      = "Claude Code / Codex events (filter by session in Explore)"
      type       = "logs"
      gridPos    = { h = 20, w = 24, x = 0, y = 0 }
      datasource = { type = "loki", uid = grafana_data_source.agent_logs.uid }
      targets    = [{ refId = "A", expr = "{service_name=~\".+\"}", queryType = "range" }]
      options    = { showTime = true, showLabels = true, sortOrder = "Descending", wrapLogMessage = true }
    }]
  })
}
