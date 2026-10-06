#!/usr/bin/env python3
"""Manage the local Langfuse/Grafana/Prometheus stack and agent integrations."""
import argparse
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
TF = ROOT / "terraform/local"
SERVICES = ("langfuse", "grafana", "prometheus", "telemetry")


def run(args, cwd=ROOT, private=False):
    if args[0] == "terraform" and "apply" in args:
        # random_id's resource ID encodes generated secrets; hide creation IDs.
        process = subprocess.Popen(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in process.stdout:
            print(re.sub(r"\[id=[^\]]+\]", "[id=redacted]", line), end="", flush=True)
        if process.wait():
            raise RuntimeError("terraform apply failed")
        return
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=private)
    if result.returncode:
        # Plugin commands can contain API keys. Never render their argv or output.
        if private:
            raise RuntimeError("Plugin configuration failed. Use /plugin configure langfuse-observability@langfuse-observability in Claude Code.")
        raise RuntimeError(f"{args[0]} failed (exit {result.returncode})")
    return result


def tf_output(name):
    result = subprocess.run(["terraform", "output", "-raw", name], cwd=TF, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError("Terraform outputs are unavailable; run 'up' first")
    return result.stdout.strip()


def connect():
    for name in ("claude", "codex", "uv", "herdr"):
        if not shutil.which(name):
            raise RuntimeError(f"Install {name} before connecting the agents")
    # Configure localhost before enabling the plugin, so it cannot fall back to cloud.
    run([sys.executable, str(ROOT / "scripts/install.py"), "--observability"])
    run(["claude", "plugin", "marketplace", "add", "langfuse/Claude-Observability-Plugin"], private=True)
    run(["claude", "plugin", "install", "langfuse-observability@langfuse-observability",
         "--scope", "user", "--config", "LANGFUSE_BASE_URL=http://127.0.0.1:3000",
         "--config", "LANGFUSE_PUBLIC_KEY=" + tf_output("langfuse_public_key"),
         "--config", "LANGFUSE_SECRET_KEY=" + tf_output("langfuse_secret_key")], private=True)
    print("Agents connected to localhost. Start new Claude Code / Codex sessions.")


def status():
    for name in SERVICES:
        run(["docker", "compose", "ps"], ROOT / "services" / name)
    for label, url in [("Langfuse", "http://127.0.0.1:3000/api/public/health"),
                       ("Grafana", "http://127.0.0.1:3001/api/health"),
                       ("Prometheus", "http://127.0.0.1:9095/-/ready"),
                       ("Collector", "http://127.0.0.1:13133/")]:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                print(f"{label}: HTTP {response.status}")
        except Exception:
            print(f"{label}: unavailable")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("up", "down", "status", "connect", "credentials"))
    parser.add_argument("--skip-connect", action="store_true", help="Start services without changing agent settings")
    args = parser.parse_args()
    if args.command == "credentials":
        # Print secrets only in a terminal explicitly opened by the user.
        if not sys.stdout.isatty():
            raise RuntimeError("Credentials can only be displayed in an interactive terminal")
        for name in ("langfuse_login_email", "langfuse_login_password", "grafana_login_user", "grafana_login_password"):
            print(f"{name}: {tf_output(name)}")
        return
    if args.command == "connect":
        connect()
        return
    if args.command == "up":
        if not shutil.which("terraform"):
            raise RuntimeError("Install Terraform 1.5+ before starting the stack")
        result = subprocess.run(["docker", "info"], capture_output=True)
        if result.returncode:
            raise RuntimeError("Docker is unreachable from this shell. Check docker context, DOCKER_HOST, and the WSL Docker socket.")
        # Terraform state also holds generated secrets.
        os.umask(0o077)
        os.environ["COMPOSE_PARALLEL_LIMIT"] = "1"
        run(["terraform", "init", "-input=false"], TF)
        run(["terraform", "validate"], TF)
        # Restart previously stopped containers before the Grafana provider refresh.
        if (TF / "terraform.tfstate").exists():
            for name in SERVICES:
                if name == "prometheus" or (ROOT / "services" / name / ".env").exists():
                    run(["docker", "compose", "--parallel", "1", "up", "-d", "--wait", "--wait-timeout", "300"], ROOT / "services" / name)
        run(["terraform", "apply", "-input=false", "-auto-approve", "-parallelism=1"], TF)
        if not args.skip_connect:
            connect()
        status()
    elif args.command == "down":
        # Preserve volumes and Terraform state, including encryption keys.
        for name in reversed(SERVICES):
            run(["docker", "compose", "stop"], ROOT / "services" / name)
    else:
        status()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, FileNotFoundError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
