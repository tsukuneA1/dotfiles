#!/usr/bin/env python3
"""Send synthetic OTLP signals and verify all three local storage backends."""
import json
import secrets
import time
import urllib.parse
import urllib.request


def request(url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)


def main():
    marker = "smoke-" + secrets.token_hex(8)
    now = str(time.time_ns())
    resource = {"attributes": [{"key": "service.name", "value": {"stringValue": "agent-o11y-smoke"}}]}
    scope = {"name": "dotfiles.smoke"}
    log = request("http://127.0.0.1:4318/v1/logs", {"resourceLogs": [{
        "resource": resource, "scopeLogs": [{"scope": scope, "logRecords": [{
            "timeUnixNano": now, "severityNumber": 9, "severityText": "INFO",
            "body": {"stringValue": marker},
        }]}],
    }]})
    metric = request("http://127.0.0.1:4318/v1/metrics", {"resourceMetrics": [{
        "resource": resource, "scopeMetrics": [{"scope": scope, "metrics": [{
            "name": "agent_o11y_smoke", "gauge": {"dataPoints": [{
                "timeUnixNano": now, "asDouble": 1,
                "attributes": [{"key": "smoke_id", "value": {"stringValue": marker}}],
            }]},
        }]}],
    }]})
    trace_id = secrets.token_hex(16)
    trace = request("http://127.0.0.1:4318/v1/traces", {"resourceSpans": [{
        "resource": resource, "scopeSpans": [{"scope": scope, "spans": [{
            "traceId": trace_id, "spanId": secrets.token_hex(8), "name": marker,
            "kind": 1, "startTimeUnixNano": now, "endTimeUnixNano": str(int(now) + 1_000_000),
            "status": {"code": 1},
        }]}],
    }]})
    for response in (log, metric, trace):
        partial = response.get("partialSuccess", {})
        assert not any(int(partial.get(key, 0)) for key in ("rejectedLogRecords", "rejectedDataPoints", "rejectedSpans")), partial
    query = urllib.parse.urlencode({"query": f'agent_o11y_smoke{{smoke_id="{marker}"}}'})
    # Query Loki through Grafana's proxy with the locally generated admin account.
    from pathlib import Path
    import base64
    import subprocess
    tf = Path(__file__).resolve().parent.parent / "terraform/local"
    def output(name):
        result = subprocess.run(["terraform", "output", "-raw", name], cwd=tf, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("Terraform outputs unavailable")
        return result.stdout.strip()
    auth = base64.b64encode((output("grafana_login_user") + ":" + output("grafana_login_password")).encode()).decode()
    langfuse_auth = base64.b64encode((output("langfuse_public_key") + ":" + output("langfuse_secret_key")).encode()).decode()
    loki_query = urllib.parse.urlencode({"query": '{service_name="agent-o11y-smoke"} |= "' + marker + '"'})
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        metrics = request("http://127.0.0.1:9095/api/v1/query?" + query)
        req = urllib.request.Request("http://127.0.0.1:3001/api/datasources/proxy/uid/agent-logs/loki/api/v1/query_range?" + loki_query,
                                     headers={"Authorization": "Basic " + auth})
        with urllib.request.urlopen(req, timeout=10) as response:
            logs = json.load(response)
        req = urllib.request.Request("http://127.0.0.1:3000/api/public/v2/observations?traceId=" + trace_id,
                                     headers={"Authorization": "Basic " + langfuse_auth})
        with urllib.request.urlopen(req, timeout=10) as response:
            observations = json.load(response)
        if metrics.get("data", {}).get("result") and logs.get("data", {}).get("result") and observations.get("data"):
            print("PASS: Prometheus, Loki, and Langfuse stored the synthetic metric, log, and trace.")
            print(f"Langfuse trace: {trace_id} ({marker})")
            return
        time.sleep(2)
    raise RuntimeError("OTLP accepted, but all three stored signals were not visible within 45 seconds")


if __name__ == "__main__":
    main()
