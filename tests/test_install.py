import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("install", ROOT / "scripts/install.py")
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)


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


if __name__ == "__main__":
    unittest.main()
