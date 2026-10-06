# Claude Code usage dashboard. Claude Code pushes its OpenTelemetry metrics
# to Prometheus's OTLP receiver (env in
# hosts/MacBookPro-minami/claude/settings.json, receiver flags in
# services/prometheus/docker-compose.yml). Datasource: prometheus.tf's
# grafana_data_source.prometheus (local.prom_ds in telemetry.tf).
#
# Every session is its own series (session_id label) that starts at 0 and
# never resets, so "how much in this range" is max - min per series rather
# than increase(), whose extrapolation overshoots on short-lived series.
# See services/README.md for the adapted local stack.

locals {
  # Sum over sessions of the increase within the dashboard's time range.
  cc_range_total = "sum(max_over_time(%s[$__range]) - min_over_time(%s[$__range]))"
  # Same, split by one label.
  cc_range_total_by = "sum by (%s) (max_over_time(%s[$__range]) - min_over_time(%s[$__range]))"

  # Claude Code pushes every 60s, so a 60s $__rate_interval (Grafana's
  # default with the datasource's 15s scrape interval) usually holds a single
  # sample and rate() returns nothing. A 2m panel minimum makes it >= 2m15s.
  cc_rate_min_interval = "2m"

  cc_cost     = "claude_code_cost_usage_USD_total"
  cc_tokens   = "claude_code_token_usage_tokens_total"
  cc_sessions = "claude_code_session_count_total"
  cc_lines    = "claude_code_lines_of_code_count_total"
  cc_active   = "claude_code_active_time_seconds_total"
}

resource "grafana_dashboard" "claude_code" {
  folder = grafana_folder.local.uid

  config_json = jsonencode({
    title         = "Claude Code Usage"
    uid           = "claude-code-usage"
    schemaVersion = 39
    time          = { from = "now-7d", to = "now" }
    panels = [
      # -- totals over the selected range --
      {
        id          = 1
        title       = "Cost (list price)"
        type        = "stat"
        gridPos     = { h = 4, w = 5, x = 0, y = 0 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "currencyUSD", decimals = 2 } }
        targets = [{
          refId   = "A"
          expr    = format(local.cc_range_total, local.cc_cost, local.cc_cost)
          instant = true
        }]
      },
      {
        id          = 2
        title       = "Sessions"
        type        = "stat"
        gridPos     = { h = 4, w = 4, x = 5, y = 0 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "none", decimals = 0 } }
        targets = [{
          refId   = "A"
          expr    = format(local.cc_range_total, local.cc_sessions, local.cc_sessions)
          instant = true
        }]
      },
      {
        id          = 3
        title       = "Tokens"
        type        = "stat"
        gridPos     = { h = 4, w = 5, x = 9, y = 0 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "short", decimals = 1 } }
        targets = [{
          refId   = "A"
          expr    = format(local.cc_range_total, local.cc_tokens, local.cc_tokens)
          instant = true
        }]
      },
      {
        id          = 4
        title       = "Lines of code"
        type        = "stat"
        gridPos     = { h = 4, w = 5, x = 14, y = 0 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "none", decimals = 0 } }
        targets = [{
          refId        = "A"
          expr         = format(local.cc_range_total_by, "type", local.cc_lines, local.cc_lines)
          instant      = true
          legendFormat = "{{type}}"
        }]
      },
      {
        id          = 5
        title       = "Active time"
        type        = "stat"
        gridPos     = { h = 4, w = 5, x = 19, y = 0 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "s" } }
        targets = [{
          refId        = "A"
          expr         = format(local.cc_range_total_by, "type", local.cc_active, local.cc_active)
          instant      = true
          legendFormat = "{{type}}"
        }]
      },
      # -- trends --
      {
        id          = 6
        title       = "Cost rate by model"
        type        = "timeseries"
        interval    = local.cc_rate_min_interval
        gridPos     = { h = 8, w = 12, x = 0, y = 4 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "currencyUSD" } }
        targets = [{
          refId        = "A"
          expr         = "sum by (model) (rate(${local.cc_cost}[$__rate_interval])) * 3600"
          legendFormat = "{{model}} ($/h)"
        }]
      },
      {
        id          = 7
        title       = "Token rate by type"
        type        = "timeseries"
        interval    = local.cc_rate_min_interval
        gridPos     = { h = 8, w = 12, x = 12, y = 4 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "short" } }
        targets = [{
          refId        = "A"
          expr         = "sum by (type) (rate(${local.cc_tokens}[$__rate_interval])) * 60"
          legendFormat = "{{type}} (/min)"
        }]
      },
      # -- breakdowns over the selected range --
      {
        id          = 8
        title       = "Cost by model"
        type        = "table"
        gridPos     = { h = 8, w = 12, x = 0, y = 12 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "currencyUSD", decimals = 2 } }
        targets = [{
          refId   = "A"
          expr    = format(local.cc_range_total_by, "model", local.cc_cost, local.cc_cost)
          instant = true
          format  = "table"
        }]
        transformations = [{
          id      = "organize"
          options = { excludeByName = { Time = true }, renameByName = { Value = "cost" } }
        }]
      },
      {
        id          = 9
        title       = "Cost by query source"
        type        = "table"
        gridPos     = { h = 8, w = 12, x = 12, y = 12 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "currencyUSD", decimals = 2 } }
        targets = [{
          refId   = "A"
          expr    = format(local.cc_range_total_by, "query_source", local.cc_cost, local.cc_cost)
          instant = true
          format  = "table"
        }]
        transformations = [{
          id      = "organize"
          options = { excludeByName = { Time = true }, renameByName = { Value = "cost" } }
        }]
      },
      # vcs_* labels come from OTEL_METRICS_INCLUDE_REPOSITORY; sessions
      # started outside a git repo with an origin remote have none (the row
      # with empty owner/repository).
      {
        id          = 10
        title       = "Cost by repository"
        type        = "table"
        gridPos     = { h = 8, w = 24, x = 0, y = 20 }
        datasource  = local.prom_ds
        fieldConfig = { defaults = { unit = "currencyUSD", decimals = 2 } }
        targets = [{
          refId   = "A"
          expr    = format(local.cc_range_total_by, "vcs_owner_name, vcs_repository_name", local.cc_cost, local.cc_cost)
          instant = true
          format  = "table"
        }]
        transformations = [{
          id = "organize"
          options = {
            excludeByName = { Time = true }
            renameByName  = { vcs_owner_name = "owner", vcs_repository_name = "repository", Value = "cost" }
          }
        }]
      },
    ]
  })

  depends_on = [grafana_data_source.prometheus]
}
