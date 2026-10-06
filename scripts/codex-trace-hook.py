#!/usr/bin/env python3
"""Turn Codex lifecycle hooks into one readable Langfuse trace per turn.

Uses only the Python standard library. Hook failures never block Codex.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time
import urllib.request

ENDPOINT = "http://127.0.0.1:4318/v1/traces"
CONTENT = os.environ.get("CODEX_LANGFUSE_CONTENT", "messages")
MAX_CONTENT = 16000


def state_root():
    xdg = os.environ.get("XDG_STATE_HOME")
    return Path(xdg) / "dotfiles/codex-traces" if xdg else Path.home() / ".local/state/dotfiles/codex-traces"


def digest(*parts):
    return hashlib.sha256("\0".join(str(part) for part in parts).encode()).hexdigest()


def state_dir(root, data):
    session, turn = data.get("session_id"), data.get("turn_id")
    if not session or not turn:
        return None
    return root / digest(session, turn)


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    with temporary.open("w") as file:
        json.dump(value, file, ensure_ascii=False)
    temporary.replace(path)


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, ValueError):
        return default


def attribute(key, value):
    if isinstance(value, list):
        return {"key": key, "value": {"arrayValue": {"values": [{"stringValue": str(item)} for item in value]}}}
    return {"key": key, "value": {"stringValue": str(value)}}


def content_value(value):
    encoded = json.dumps(value, ensure_ascii=False, default=str)
    if len(encoded) > MAX_CONTENT:
        encoded = json.dumps({"truncated": True, "preview": encoded[:MAX_CONTENT]}, ensure_ascii=False)
    return encoded


def span(trace_id, span_id, name, started, ended, attributes, parent=None, error=False):
    result = {
        "traceId": trace_id,
        "spanId": span_id,
        "name": name,
        "startTimeUnixNano": str(started),
        "endTimeUnixNano": str(max(started, ended)),
        "attributes": [attribute(key, value) for key, value in attributes.items()],
    }
    if parent:
        result["parentSpanId"] = parent
    if error:
        result["status"] = {"code": 2}
    return result


def build_payload(data, directory, ended, content_mode):
    session, turn = data["session_id"], data["turn_id"]
    trace_id = digest(session, turn)[:32]
    root_id = digest(session, turn, "root")[:16]
    root = read_json(directory / "root.json", {})
    project = Path(root.get("cwd") or data.get("cwd") or "unknown").name or "unknown"
    common = {
        "langfuse.trace.name": f"Codex · {project}",
        "langfuse.session.id": session,
        "langfuse.trace.tags": ["codex-hook"],
        "langfuse.trace.metadata.project": project,
    }
    root_attrs = {
        **common,
        "langfuse.observation.type": "agent",
        "langfuse.observation.metadata.model": root.get("model") or data.get("model") or "unknown",
        "langfuse.observation.metadata.turn_id": turn,
    }
    if content_mode in ("messages", "all"):
        if root.get("prompt") is not None:
            root_attrs["langfuse.observation.input"] = content_value(root["prompt"])
        if data.get("last_assistant_message") is not None:
            root_attrs["langfuse.observation.output"] = content_value(data["last_assistant_message"])
    if data.get("hook_event_name") == "Interrupt":
        root_attrs["langfuse.observation.status_message"] = "Interrupted"
    spans = [span(trace_id, root_id, f"Codex · {project}", root.get("started", ended), ended,
                  root_attrs, error=data.get("hook_event_name") == "Interrupt")]
    for path in sorted(directory.glob("tool-*.json")):
        tool = read_json(path, {})
        if not tool:
            continue
        tool_attrs = {
            **common,
            "langfuse.observation.type": "tool",
            "langfuse.observation.metadata.tool_name": tool.get("name", "unknown"),
        }
        if content_mode == "all":
            if "input" in tool:
                tool_attrs["langfuse.observation.input"] = content_value(tool["input"])
            if "output" in tool:
                tool_attrs["langfuse.observation.output"] = content_value(tool["output"])
        if "ended" not in tool:
            tool_attrs["langfuse.observation.status_message"] = "Tool did not complete before turn ended"
        tool_id = path.stem.removeprefix("tool-")
        spans.append(span(trace_id, tool_id[:16], tool.get("name", "tool"), tool.get("started", ended),
                          tool.get("ended", ended), tool_attrs, parent=root_id,
                          error=tool.get("error", False) or "ended" not in tool))
    return {"resourceSpans": [{
        "resource": {"attributes": [attribute("service.name", "codex-hook-trace")]},
        "scopeSpans": [{"scope": {"name": "dotfiles.codex-trace-hook"}, "spans": spans}],
    }]}


def export(payload):
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=1) as response:
        return 200 <= response.status < 300


def flush_pending(root, limit=1):
    if not root.exists():
        return
    count = 0
    for directory in root.iterdir():
        pending = directory / "pending.json"
        if not pending.is_file():
            continue
        payload = read_json(pending)
        if payload is None:
            continue
        try:
            if export(payload):
                shutil.rmtree(directory)
        except OSError:
            pass
        count += 1
        if count >= limit:
            break


def handle(data, root=None, content_mode=None):
    root = root or state_root()
    content_mode = content_mode or CONTENT
    directory = state_dir(root, data)
    if directory is None:
        return
    event = data.get("hook_event_name")
    now = time.time_ns()
    if event == "UserPromptSubmit":
        item = {"started": now, "cwd": data.get("cwd"), "model": data.get("model")}
        if content_mode in ("messages", "all"):
            item["prompt"] = data.get("prompt")
        save_json(directory / "root.json", item)
        flush_pending(root)
    elif event in ("PreToolUse", "PostToolUse"):
        call_id = data.get("tool_use_id")
        if not call_id:
            return
        path = directory / ("tool-" + digest(call_id)[:16] + ".json")
        item = read_json(path, {})
        if event == "PreToolUse":
            item.update({"started": now, "name": data.get("tool_name", "tool")})
            if content_mode == "all":
                item["input"] = data.get("tool_input")
        else:
            item.setdefault("started", now)
            item.setdefault("name", data.get("tool_name", "tool"))
            item["ended"] = now
            response = data.get("tool_response")
            item["error"] = bool(isinstance(response, dict) and
                                 (response.get("isError") or response.get("exit_code") not in (None, 0)))
            if content_mode == "all":
                item["output"] = response
        save_json(path, item)
    elif event in ("Stop", "Interrupt"):
        payload = build_payload(data, directory, now, content_mode)
        save_json(directory / "pending.json", payload)
        try:
            if export(payload):
                shutil.rmtree(directory)
        except OSError:
            pass


def main():
    data = {}
    try:
        data = json.load(sys.stdin)
        if isinstance(data, dict):
            handle(data)
        else:
            data = {}
    except Exception:
        # Telemetry must never interrupt the agent. Pending traces can retry later.
        pass
    if data.get("hook_event_name") == "Stop":
        print("{}")


if __name__ == "__main__":
    main()
