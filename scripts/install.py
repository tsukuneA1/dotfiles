#!/usr/bin/env python3
"""Apply shared preferences without copying credentials or machine state."""

import argparse
import copy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tomllib

REPO = Path(__file__).resolve().parent.parent


def merge_json(current, shared):
    result = copy.deepcopy(current)
    for key, value in shared.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge_json(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def merge_codex(current, shared):
    """Update root preferences and selected tables, retaining machine state."""
    original = tomllib.loads(current)
    expected = copy.deepcopy(original)
    root = {k: v for k, v in shared.items() if not isinstance(v, dict)}
    tables = {k: v for k, v in shared.items() if isinstance(v, dict)}
    expected.update(root)
    for table, values in tables.items():
        expected.setdefault(table, {}).update(copy.deepcopy(values))
    lines = current.splitlines(keepends=True)

    def literal(value):
        if isinstance(value, dict):
            return "{ " + ", ".join(f"{json.dumps(k)} = {literal(v)}" for k, v in value.items()) + " }"
        if isinstance(value, (str, bool, int)):
            return json.dumps(value, ensure_ascii=False)
        raise ValueError("Unsupported shared TOML value")

    for table, values in [("", root), *tables.items()]:
        if not values:
            continue
        headers = [i for i, line in enumerate(lines) if line.lstrip().startswith("[")]
        if table:
            matches = [i for i in headers if re.fullmatch(r"\[" + re.escape(table) + r"\]\s*(?:#.*)?", lines[i].strip())]
            if matches:
                start = matches[0] + 1
            else:
                lines.append(f"\n[{table}]\n")
                start = len(lines)
        else:
            start = 0
        end = next((i for i in headers if i >= start), len(lines))
        keys = "|".join(re.escape(k) for k in values)
        pattern = re.compile(r"^\s*(?:" + keys + r")\s*=")
        retained = [line for line in lines[start:end] if not pattern.match(line)]
        rendered = [f"{key} = {literal(value)}\n" for key, value in values.items()]
        lines[start:end] = rendered + retained
    result = "".join(lines)
    if tomllib.loads(result) != expected:
        raise ValueError("Cannot safely merge this Codex config; no files changed")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home(), help="Target home (for preview/testing)")
    parser.add_argument("--skip-integrations", action="store_true", help="Apply preferences only")
    parser.add_argument("--observability", action="store_true", help="Enable local telemetry exporters")
    args = parser.parse_args()
    home = args.home.expanduser().resolve()
    if not args.skip_integrations and home != Path.home().resolve():
        parser.error("Use --skip-integrations with an alternate --home")
    if not args.skip_integrations and not shutil.which("herdr"):
        parser.error("Install Herdr first: https://herdr.dev/docs/install/")

    claude = home / ".claude/settings.json"
    codex = home / ".codex/config.toml"
    # Respect XDG_CONFIG_HOME for the real user; alternate homes are isolated.
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(home / ".config"))) if home == Path.home().resolve() else home / ".config"
    herdr = config_home / "herdr/config.toml"
    claude_current = json.loads(claude.read_text()) if claude.exists() else {}
    codex_current = codex.read_text() if codex.exists() else ""
    claude_shared = json.loads((REPO / "claude/settings.json").read_text())
    codex_shared = tomllib.loads((REPO / "codex/config.toml").read_text())
    if args.observability:
        claude_shared = merge_json(claude_shared, json.loads((REPO / "observability/claude.settings.json").read_text()))
        codex_shared.update(tomllib.loads((REPO / "observability/codex.config.toml").read_text()))
    herdr_source = REPO / "herdr/config.toml"
    tomllib.loads(herdr_source.read_text())
    # Validate everything before touching the real configuration.
    changes = {
        claude: json.dumps(merge_json(claude_current, claude_shared), ensure_ascii=False, indent=2) + "\n",
        codex: merge_codex(codex_current, codex_shared),
    }
    backup = home / ".local/state/dotfiles/backups" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")

    def save(path):
        if path.exists():
            backup.mkdir(parents=True, exist_ok=True, mode=0o700)
            target = backup / (str(path).replace("/", "__").lstrip("_"))
            if target.exists():
                return
            shutil.copy2(path, target)
            target.chmod(0o600)

    for path, content in changes.items():
        if path.exists() and path.read_text() == content:
            print(f"Unchanged: {path}")
            continue
        save(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        print(f"Applied: {path}")
    if not (herdr.is_symlink() and herdr.resolve() == herdr_source):
        save(herdr)
        herdr.parent.mkdir(parents=True, exist_ok=True)
        if herdr.exists() or herdr.is_symlink():
            herdr.unlink()
        herdr.symlink_to(herdr_source)
        print(f"Linked: {herdr}")

    if not args.skip_integrations:
        # Let Herdr generate version-appropriate hooks and paths on each machine.
        for path in [claude, codex, home / ".codex/hooks.json",
                     home / ".claude/hooks/herdr-agent-state.sh",
                     home / ".codex/herdr-agent-state.sh"]:
            save(path)
        for agent in ("claude", "codex"):
            subprocess.run(["herdr", "integration", "install", agent], check=True)
    if backup.exists():
        print(f"Backups: {backup}")


if __name__ == "__main__":
    main()
