# Agent/Cost/Latency dashboards from Langfuse's own Dashboards page, filling
# in what langfuse_grafana.tf (Home) doesn't cover. See
# services/README.md for the adapted local stack.

locals {
  # piechart/bargauge default to aggregating all rows into one value; this
  # keeps each row as its own value (matches Langfuse UI's chart style).
  multi_value_options = { reduceOptions = { values = true, calcs = [] } }

  q_total_tool_calls = <<-SQL
    SELECT count() AS tool_calls FROM events_core
    WHERE is_deleted = 0 AND type = 'TOOL' AND $__timeFilter(start_time)
  SQL

  q_top_called_tools = <<-SQL
    SELECT name, count() AS calls FROM events_core
    WHERE is_deleted = 0 AND type = 'TOOL' AND $__timeFilter(start_time)
    GROUP BY name ORDER BY calls DESC LIMIT 20
  SQL

  q_observations_by_type = <<-SQL
    SELECT type, count() AS observations FROM events_core
    WHERE is_deleted = 0 AND $__timeFilter(start_time)
    GROUP BY type
  SQL

  q_tool_calls_by_time = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, count() AS tool_calls
    FROM events_core
    WHERE is_deleted = 0 AND type = 'TOOL' AND $__timeFilter(start_time)
    GROUP BY time ORDER BY time
  SQL

  q_tool_latency = <<-SQL
    SELECT name, quantile(0.95)(${local.ch_duration_expr}) AS p95 FROM events_core
    WHERE is_deleted = 0 AND type = 'TOOL' AND $__timeFilter(start_time)
    GROUP BY name ORDER BY p95 DESC LIMIT 20
  SQL

  q_tool_errors = <<-SQL
    SELECT name, count() AS errors FROM events_core
    WHERE is_deleted = 0 AND type = 'TOOL' AND level = 'ERROR' AND $__timeFilter(start_time)
    GROUP BY name ORDER BY errors DESC LIMIT 20
  SQL

  q_latency_by_observation_type = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, type,
      quantile(0.95)(${local.ch_duration_expr}) AS p95
    FROM events_core
    WHERE is_deleted = 0 AND $__timeFilter(start_time)
    GROUP BY time, type ORDER BY time
  SQL

  q_tool_latency_by_time = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, name,
      quantile(0.95)(${local.ch_duration_expr}) AS p95
    FROM events_core
    WHERE is_deleted = 0 AND type = 'TOOL' AND $__timeFilter(start_time)
    GROUP BY time, name ORDER BY time
  SQL

  q_cost_by_environment = <<-SQL
    SELECT environment, sum(total_cost) AS cost FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY environment
  SQL

  q_cost_by_trace_name = <<-SQL
    SELECT trace_name, sum(total_cost) AS cost FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY trace_name ORDER BY cost DESC LIMIT 20
  SQL

  q_cost_by_observation_name = <<-SQL
    SELECT name, sum(total_cost) AS cost FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY name ORDER BY cost DESC LIMIT 20
  SQL

  q_cost_by_user = <<-SQL
    SELECT if(user_id = '', 'Unknown', user_id) AS user, sum(total_cost) AS cost
    FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY user ORDER BY cost DESC LIMIT 20
  SQL

  q_p95_cost_per_trace = <<-SQL
    SELECT toStartOfInterval(min_start, INTERVAL 1 hour) AS time, quantile(0.95)(trace_cost) AS p95
    FROM (
      SELECT trace_id, min(start_time) AS min_start, sum(total_cost) AS trace_cost
      FROM events_core
      WHERE is_deleted = 0 AND $__timeFilter(start_time)
      GROUP BY trace_id
    )
    GROUP BY time ORDER BY time
  SQL

  q_p95_input_cost = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time,
      quantile(0.95)(cost_details['input']) AS p95
    FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY time ORDER BY time
  SQL

  q_p95_output_cost = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time,
      quantile(0.95)(cost_details['output']) AS p95
    FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY time ORDER BY time
  SQL

  q_latency_by_use_case = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, trace_name,
      quantile(0.95)(${local.ch_duration_expr}) AS p95
    FROM events_core
    WHERE is_deleted = 0 AND is_app_root = 1 AND $__timeFilter(start_time)
    GROUP BY time, trace_name ORDER BY time
  SQL

  q_latency_by_level = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, level,
      quantile(0.95)(${local.ch_duration_expr}) AS p95
    FROM events_core
    WHERE is_deleted = 0 AND $__timeFilter(start_time)
    GROUP BY time, level ORDER BY time
  SQL

  q_max_latency_by_user = <<-SQL
    SELECT if(user_id = '', 'Unknown', user_id) AS user,
      max(${local.ch_duration_expr}) AS max_ms
    FROM events_core
    WHERE is_deleted = 0 AND is_app_root = 1 AND $__timeFilter(start_time)
    GROUP BY user ORDER BY max_ms DESC LIMIT 50
  SQL

  q_latency_by_model = <<-SQL
    SELECT toStartOfInterval(start_time, INTERVAL 1 hour) AS time, provided_model_name AS model,
      quantile(0.95)(${local.ch_duration_expr}) AS p95
    FROM events_core
    WHERE is_deleted = 0 AND type = 'GENERATION' AND $__timeFilter(start_time)
    GROUP BY time, model ORDER BY time
  SQL
}

# -- Agent dashboard --
resource "grafana_dashboard" "langfuse_agent" {
  folder = grafana_folder.local.uid

  config_json = jsonencode({
    title         = "Langfuse Agent"
    uid           = "langfuse-agent"
    schemaVersion = 39
    time          = { from = "now-1d", to = "now" }
    panels = [
      {
        id         = 1
        title      = "Total Tool Calls"
        type       = "stat"
        gridPos    = { h = 8, w = 6, x = 0, y = 0 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_total_tool_calls }]
      },
      {
        id         = 2
        title      = "Observations by Type"
        type       = "piechart"
        gridPos    = { h = 8, w = 9, x = 6, y = 0 }
        datasource = local.ch_ds
        options    = local.multi_value_options
        targets    = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_observations_by_type }]
      },
      {
        id         = 3
        title      = "Top 20 Called Tools"
        type       = "bargauge"
        gridPos    = { h = 8, w = 9, x = 15, y = 0 }
        datasource = local.ch_ds
        options    = local.multi_value_options
        targets    = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_top_called_tools }]
      },
      {
        id         = 4
        title      = "Total Tool Calls (over time)"
        type       = "timeseries"
        gridPos    = { h = 8, w = 12, x = 0, y = 8 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_tool_calls_by_time }]
      },
      {
        id         = 5
        title      = "P95 Tool Latency by Tool (ms)"
        type       = "bargauge"
        gridPos    = { h = 8, w = 12, x = 12, y = 8 }
        datasource = local.ch_ds
        options    = local.multi_value_options
        targets    = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_tool_latency }]
      },
      {
        id         = 6
        title      = "Tool Errors by Tool"
        type       = "table"
        gridPos    = { h = 8, w = 12, x = 0, y = 16 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_tool_errors }]
      },
      {
        id         = 7
        title      = "P95 Latency by Observation Type (ms)"
        type       = "timeseries"
        gridPos    = { h = 8, w = 12, x = 12, y = 16 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_latency_by_observation_type }]
      },
      {
        id         = 8
        title      = "P95 Tool Latency by Tool (over time, ms)"
        type       = "timeseries"
        gridPos    = { h = 8, w = 24, x = 0, y = 24 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_tool_latency_by_time }]
      },
    ]
  })

  depends_on = [grafana_data_source.langfuse_clickhouse]
}

# -- Cost dashboard --
resource "grafana_dashboard" "langfuse_cost" {
  folder = grafana_folder.local.uid

  config_json = jsonencode({
    title         = "Langfuse Cost"
    uid           = "langfuse-cost"
    schemaVersion = 39
    time          = { from = "now-1d", to = "now" }
    panels = [
      {
        id          = 1
        title       = "Cost by Environment"
        type        = "piechart"
        gridPos     = { h = 8, w = 8, x = 0, y = 0 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        options     = local.multi_value_options
        targets     = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_cost_by_environment }]
      },
      {
        id          = 2
        title       = "Top 20 Use Cases (Trace) by Cost"
        type        = "bargauge"
        gridPos     = { h = 8, w = 8, x = 8, y = 0 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        options     = local.multi_value_options
        targets     = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_cost_by_trace_name }]
      },
      {
        id          = 3
        title       = "Top 20 Use Cases (Observation) by Cost"
        type        = "bargauge"
        gridPos     = { h = 8, w = 8, x = 16, y = 0 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        options     = local.multi_value_options
        targets     = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_cost_by_observation_name }]
      },
      {
        id          = 4
        title       = "Top 20 Users by Cost"
        type        = "bargauge"
        gridPos     = { h = 8, w = 12, x = 0, y = 8 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        options     = local.multi_value_options
        targets     = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_cost_by_user }]
      },
      {
        id          = 5
        title       = "P95 Cost per Trace"
        type        = "timeseries"
        gridPos     = { h = 8, w = 12, x = 12, y = 8 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        targets     = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_p95_cost_per_trace }]
      },
      {
        id          = 6
        title       = "P95 Input Cost per Observation"
        type        = "timeseries"
        gridPos     = { h = 8, w = 12, x = 0, y = 16 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        targets     = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_p95_input_cost }]
      },
      {
        id          = 7
        title       = "P95 Output Cost per Observation"
        type        = "timeseries"
        gridPos     = { h = 8, w = 12, x = 12, y = 16 }
        datasource  = local.ch_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        targets     = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_p95_output_cost }]
      },
    ]
  })

  depends_on = [grafana_data_source.langfuse_clickhouse]
}

# -- Latency dashboard --
resource "grafana_dashboard" "langfuse_latency" {
  folder = grafana_folder.local.uid

  config_json = jsonencode({
    title         = "Langfuse Latency"
    uid           = "langfuse-latency"
    schemaVersion = 39
    time          = { from = "now-1d", to = "now" }
    panels = [
      {
        id         = 1
        title      = "P95 Latency by Use Case (ms)"
        type       = "timeseries"
        gridPos    = { h = 8, w = 12, x = 0, y = 0 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_latency_by_use_case }]
      },
      {
        id         = 2
        title      = "P95 Latency by Level (ms)"
        type       = "timeseries"
        gridPos    = { h = 8, w = 12, x = 12, y = 0 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_latency_by_level }]
      },
      {
        id         = 3
        title      = "Max Latency by User Id (Traces, ms)"
        type       = "table"
        gridPos    = { h = 8, w = 12, x = 0, y = 8 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 1, rawSql = local.q_max_latency_by_user }]
      },
      {
        id         = 4
        title      = "P95 Latency by Model (ms)"
        type       = "timeseries"
        gridPos    = { h = 8, w = 12, x = 12, y = 8 }
        datasource = local.ch_ds
        targets    = [{ refId = "A", editorType = "sql", format = 0, rawSql = local.q_latency_by_model }]
      },
    ]
  })

  depends_on = [grafana_data_source.langfuse_clickhouse]
}
