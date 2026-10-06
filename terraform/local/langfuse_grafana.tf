# ClickHouse datasource + dashboards for Langfuse's own trace data
# (services/langfuse's ClickHouse, events_core table). See
# services/README.md for the grafana_ro user design and
# dashboard verification notes.

resource "random_password" "clickhouse_grafana_ro" {
  length  = 32
  special = false
}

# Defined via ClickHouse's users.d config, not SQL — see rules for why.
resource "local_sensitive_file" "clickhouse_grafana_ro_users_xml" {
  filename        = "${local.langfuse_dir}/clickhouse-users.d/grafana-ro.xml"
  file_permission = "0600"

  content = <<-EOT
    <clickhouse>
      <!-- readonly=2, not 1: allows session SET (needed by the Grafana plugin) but blocks writes. -->
      <profiles>
        <grafana_ro_profile>
          <readonly>2</readonly>
        </grafana_ro_profile>
      </profiles>
      <users>
        <grafana_ro>
          <password_sha256_hex>${sha256(random_password.clickhouse_grafana_ro.result)}</password_sha256_hex>
          <networks>
            <ip>::/0</ip>
          </networks>
          <profile>grafana_ro_profile</profile>
          <quota>default</quota>
          <access_management>0</access_management>
        </grafana_ro>
      </users>
    </clickhouse>
  EOT
}

resource "grafana_data_source" "langfuse_clickhouse" {
  type = "grafana-clickhouse-datasource"
  name = "Langfuse (ClickHouse)"

  json_data_encoded = jsonencode({
    host            = "clickhouse"
    port            = 8123
    protocol        = "http"
    secure          = false
    username        = "grafana_ro"
    defaultDatabase = "default"
  })

  secure_json_data_encoded = jsonencode({
    password = random_password.clickhouse_grafana_ro.result
  })

  depends_on = [
    terraform_data.grafana_compose_up,
    terraform_data.compose_up,
  ]
}

# Reproduces Langfuse's Home dashboard as raw SQL against events_core.
# Upstream was verified against the Langfuse UI (http://localhost:3000) via
# /api/ds/query. Scores panels excluded: no score data in this project.
locals {
  ch_ds = { type = "grafana-clickhouse-datasource", uid = grafana_data_source.langfuse_clickhouse.uid }

  ch_duration_expr = "dateDiff('millisecond', start_time, end_time)"

  q_traces = <<-SQL
    SELECT count() AS traces FROM events_core
    WHERE is_deleted = 0 AND is_app_root = 1 AND $__timeFilter(start_time)
  SQL

  q_total_cost = <<-SQL
    SELECT sum(total_cost) AS total_cost FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
  SQL

  q_observations = <<-SQL
    SELECT count() AS observations FROM events_core
    WHERE is_deleted = 0 AND $__timeFilter(start_time)
  SQL

  q_observations_by_time = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, count() AS observations
    FROM events_core
    WHERE is_deleted = 0 AND $__timeFilter(start_time)
    GROUP BY time ORDER BY time
  SQL

  q_cost_by_time = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, sum(total_cost) AS cost
    FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY time ORDER BY time
  SQL

  q_model_usage = <<-SQL
    SELECT provided_model_name AS model, sum(usage_details['total']) AS tokens,
      sum(total_cost) AS cost_usd
    FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY model ORDER BY cost_usd DESC
  SQL

  q_trace_latency = <<-SQL
    SELECT trace_name,
      quantile(0.5)(${local.ch_duration_expr}) AS p50,
      quantile(0.9)(${local.ch_duration_expr}) AS p90,
      quantile(0.95)(${local.ch_duration_expr}) AS p95,
      quantile(0.99)(${local.ch_duration_expr}) AS p99
    FROM events_core
    WHERE is_deleted = 0 AND is_app_root = 1 AND $__timeFilter(start_time)
    GROUP BY trace_name ORDER BY p95 DESC
  SQL

  q_generation_latency = <<-SQL
    SELECT name,
      quantile(0.5)(${local.ch_duration_expr}) AS p50,
      quantile(0.9)(${local.ch_duration_expr}) AS p90,
      quantile(0.95)(${local.ch_duration_expr}) AS p95,
      quantile(0.99)(${local.ch_duration_expr}) AS p99
    FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY name ORDER BY p95 DESC
  SQL

  q_observation_latency = <<-SQL
    SELECT type, name,
      quantile(0.5)(${local.ch_duration_expr}) AS p50,
      quantile(0.9)(${local.ch_duration_expr}) AS p90,
      quantile(0.95)(${local.ch_duration_expr}) AS p95,
      quantile(0.99)(${local.ch_duration_expr}) AS p99
    FROM events_core
    WHERE is_deleted = 0 AND $__timeFilter(start_time)
    GROUP BY type, name ORDER BY type, p95 DESC
  SQL
}

resource "grafana_dashboard" "langfuse_overview" {
  folder = grafana_folder.local.uid

  config_json = jsonencode({
    title         = "Langfuse Overview"
    uid           = "langfuse-overview"
    schemaVersion = 39
    time          = { from = "now-1d", to = "now" }
    panels = [
      # -- summary stats (Traces / Model costs / Scores in Langfuse Home) --
      {
        id         = 1
        title      = "Traces"
        type       = "stat"
        gridPos    = { h = 4, w = 8, x = 0, y = 0 }
        datasource = local.ch_ds
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 1
          rawSql     = local.q_traces
        }]
      },
      {
        id          = 2
        title       = "Total Cost"
        type        = "stat"
        gridPos     = { h = 4, w = 8, x = 8, y = 0 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 1
          rawSql     = local.q_total_cost
        }]
      },
      {
        id         = 3
        title      = "Observations"
        type       = "stat"
        gridPos    = { h = 4, w = 8, x = 16, y = 0 }
        datasource = local.ch_ds
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 1
          rawSql     = local.q_observations
        }]
      },
      # -- time series (Observations by time / Model Usage in Langfuse Home) --
      {
        id         = 4
        title      = "Observations by time"
        type       = "timeseries"
        gridPos    = { h = 8, w = 12, x = 0, y = 4 }
        datasource = local.ch_ds
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 0
          rawSql     = local.q_observations_by_time
        }]
      },
      {
        id          = 5
        title       = "Cost by time"
        type        = "timeseries"
        gridPos     = { h = 8, w = 12, x = 12, y = 4 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 0
          rawSql     = local.q_cost_by_time
        }]
      },
      # -- tables (Model costs / *latency percentiles in Langfuse Home) --
      {
        id         = 6
        title      = "Model usage"
        type       = "table"
        gridPos    = { h = 8, w = 12, x = 0, y = 12 }
        datasource = local.ch_ds
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 1
          rawSql     = local.q_model_usage
        }]
      },
      {
        id         = 7
        title      = "Trace latency percentiles (ms)"
        type       = "table"
        gridPos    = { h = 8, w = 12, x = 12, y = 12 }
        datasource = local.ch_ds
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 1
          rawSql     = local.q_trace_latency
        }]
      },
      {
        id         = 8
        title      = "Generation latency percentiles (ms)"
        type       = "table"
        gridPos    = { h = 8, w = 12, x = 0, y = 20 }
        datasource = local.ch_ds
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 1
          rawSql     = local.q_generation_latency
        }]
      },
      {
        id         = 9
        title      = "Observation latency percentiles (ms)"
        type       = "table"
        gridPos    = { h = 8, w = 12, x = 12, y = 20 }
        datasource = local.ch_ds
        targets = [{
          refId      = "A"
          editorType = "sql"
          format     = 1
          rawSql     = local.q_observation_latency
        }]
      },
    ]
  })

  depends_on = [grafana_data_source.langfuse_clickhouse]
}
