import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("install", ROOT / "scripts/install.py")
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)
trace_spec = importlib.util.spec_from_file_location("codex_trace_hook", ROOT / "scripts/codex-trace-hook.py")
trace_hook = importlib.util.module_from_spec(trace_spec)
trace_spec.loader.exec_module(trace_hook)


class InstallTests(unittest.TestCase):
    def test_observability_preserves_local_state_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".claude").mkdir()
            (home / ".codex").mkdir()
            (home / ".config/fish").mkdir(parents=True)
            (home / ".config/fish/config.fish").write_text("# local fish config\n")
            (home / ".bashrc").write_text("# local bash config\n")
            original_claude = {"env": {"KEEP_LOCAL": "value"}, "hooks": {"SessionStart": []},
                               "permissions": {"allow": ["Read"]}}
            original_codex = '[projects."/tmp/private"]\ntrust_level = "trusted"\n[features]\nother_feature = true\n'
            (home / ".claude/settings.json").write_text(json.dumps(original_claude))
            (home / ".codex/config.toml").write_text(original_codex)
            cmd = ["python3", str(ROOT / "scripts/install.py"), "--home", directory,
                   "--skip-integrations", "--observability"]
            subprocess.run(cmd, check=True, capture_output=True)
            first = [(home / file).read_text() for file in (".claude/settings.json", ".codex/config.toml")]
            fish = home / ".config/fish/config.fish"
            self.assertTrue(fish.is_symlink())
            self.assertEqual(fish.resolve(), ROOT / "fish/config.fish")
            backups = list((home / ".local/state/dotfiles/backups").glob("*/**/*fish__config.fish"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), "# local fish config\n")
            bashrc_first = (home / ".bashrc").read_text()
            self.assertIn("# local bash config\n", bashrc_first)
            self.assertEqual(bashrc_first.count(install.BASH_BEGIN), 1)
            subprocess.run(cmd, check=True, capture_output=True)
            self.assertEqual((home / ".bashrc").read_text(), bashrc_first)
            self.assertEqual(len(list((home / ".local/state/dotfiles/backups").glob("*/**/*fish__config.fish"))), 1)
            self.assertEqual(first, [(home / file).read_text() for file in (".claude/settings.json", ".codex/config.toml")])
            claude, codex = json.loads(first[0]), tomllib.loads(first[1])
            self.assertEqual(claude["env"]["KEEP_LOCAL"], "value")
            self.assertEqual(claude["hooks"], original_claude["hooks"])
            self.assertEqual(claude["permissions"]["allow"], ["Read"])
            self.assertEqual(codex["projects"]["/tmp/private"]["trust_level"], "trusted")
            self.assertTrue(codex["features"]["other_feature"])
            self.assertEqual(codex["otel"]["exporter"]["otlp-http"]["endpoint"], "http://127.0.0.1:4318/v1/logs")
            self.assertEqual(codex["otel"]["trace_exporter"], "none")
            hooks = json.loads((home / ".codex/hooks.json").read_text())["hooks"]
            for event in install.CODEX_TRACE_EVENTS:
                self.assertEqual(len(hooks[event]), 1)
                self.assertIn("codex-trace-hook.py", hooks[event][0]["hooks"][0]["command"])

    def test_unrecognized_toml_layout_fails_without_rewriting(self):
        shared = {"otel": {"exporter": {"otlp-http": {"endpoint": "http://localhost"}}}}
        with self.assertRaises(ValueError):
            install.merge_codex('[otel.exporter.otlp-http]\nendpoint = "old"\n', shared)

    def test_bashrc_with_unbalanced_markers_fails(self):
        with self.assertRaises(ValueError):
            install.merge_bashrc(install.BASH_BEGIN + "\n", (ROOT / "bash/exec-fish.bash").read_text())

    def test_shell_only_does_not_apply_other_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".bashrc").write_text("# local startup\n")
            cmd = ["python3", str(ROOT / "scripts/install.py"), "--home", directory, "--shell-only"]
            subprocess.run(cmd, check=True, capture_output=True)
            self.assertEqual((home / ".bashrc").read_text().count(install.BASH_BEGIN), 1)
            self.assertTrue((home / ".config/fish/config.fish").is_symlink())
            self.assertFalse((home / ".claude").exists())
            self.assertFalse((home / ".codex").exists())
            self.assertFalse((home / ".config/herdr").exists())

    def test_codex_trace_hooks_preserve_existing_hooks(self):
        current = {"hooks": {"SessionStart": [{"hooks": [{"command": "herdr session"}]}],
                             "Stop": [{"hooks": [{"command": "other stop"}]}]}}
        merged = install.merge_codex_trace_hooks(current, "python3 /repo/scripts/codex-trace-hook.py")
        self.assertEqual(merged["hooks"]["SessionStart"], current["hooks"]["SessionStart"])
        self.assertEqual(merged["hooks"]["Stop"][0], current["hooks"]["Stop"][0])
        self.assertEqual(install.merge_codex_trace_hooks(merged, "python3 /repo/scripts/codex-trace-hook.py"), merged)

    def test_codex_trace_has_turn_and_tool_without_tool_body(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            base = {"session_id": "session-1", "turn_id": "turn-1", "cwd": "/repo/project", "model": "gpt-test"}
            with patch.object(trace_hook, "export", return_value=True) as send:
                trace_hook.handle({**base, "hook_event_name": "UserPromptSubmit", "prompt": "Fix the issue"}, state, "messages")
                trace_hook.handle({**base, "hook_event_name": "PreToolUse", "tool_use_id": "call-1",
                                   "tool_name": "Bash", "tool_input": {"command": "secret command"}}, state, "messages")
                trace_hook.handle({**base, "hook_event_name": "PostToolUse", "tool_use_id": "call-1",
                                   "tool_name": "Bash", "tool_response": {"output": "secret output"}}, state, "messages")
                trace_hook.handle({**base, "hook_event_name": "Stop", "last_assistant_message": "Fixed"}, state, "messages")
            payload = send.call_args.args[0]
            root, tool = payload["resourceSpans"][0]["scopeSpans"][0]["spans"]
            self.assertEqual(tool["parentSpanId"], root["spanId"])
            self.assertEqual(tool["traceId"], root["traceId"])
            root_attrs = {item["key"]: item["value"] for item in root["attributes"]}
            tool_attrs = {item["key"]: item["value"] for item in tool["attributes"]}
            self.assertEqual(root_attrs["langfuse.observation.input"]["stringValue"], '"Fix the issue"')
            self.assertEqual(root_attrs["langfuse.observation.output"]["stringValue"], '"Fixed"')
            self.assertNotIn("langfuse.observation.input", tool_attrs)
            self.assertNotIn("langfuse.observation.output", tool_attrs)
            self.assertFalse(any(state.iterdir()))

    def test_codex_traces_only_preserves_other_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / ".codex").mkdir()
            (home / ".codex/config.toml").write_text('model = "local-choice"\n')
            (home / ".codex/hooks.json").write_text(json.dumps({
                "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "herdr session"}]}]}
            }))
            subprocess.run(["python3", str(ROOT / "scripts/install.py"), "--home", directory,
                            "--codex-traces-only"], check=True, capture_output=True)
            config = tomllib.loads((home / ".codex/config.toml").read_text())
            hooks = json.loads((home / ".codex/hooks.json").read_text())["hooks"]
            self.assertEqual(config["model"], "local-choice")
            self.assertEqual(config["otel"]["trace_exporter"], "none")
            self.assertEqual(hooks["SessionStart"][0]["hooks"][0]["command"], "herdr session")
            self.assertFalse((home / ".claude").exists())
            self.assertFalse((home / ".bashrc").exists())
            self.assertFalse((home / ".config").exists())

    def test_codex_trace_retries_when_collector_is_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            first = {"session_id": "session-1", "turn_id": "turn-1"}
            with patch.object(trace_hook, "export", side_effect=OSError("offline")):
                trace_hook.handle({**first, "hook_event_name": "UserPromptSubmit", "prompt": "Request"}, state, "messages")
                trace_hook.handle({**first, "hook_event_name": "Stop", "last_assistant_message": "Reply"}, state, "messages")
            pending = trace_hook.state_dir(state, first) / "pending.json"
            self.assertTrue(pending.is_file())
            with patch.object(trace_hook, "export", return_value=True) as send:
                trace_hook.handle({"session_id": "session-1", "turn_id": "turn-2",
                                   "hook_event_name": "UserPromptSubmit", "prompt": "Next"}, state, "messages")
            self.assertEqual(send.call_count, 1)
            self.assertFalse(pending.exists())


if __name__ == "__main__":
    unittest.main()
