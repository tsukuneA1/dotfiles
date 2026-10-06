# dotfiles

Claude Code、Codex、Herdr、fish の共通設定。

ローカルの実行履歴・使用量を記録する **Langfuse / Grafana / Prometheus** は
[services/README.md](services/README.md) を参照。

## 適用

Python 3.11以上と、ログイン済みのClaude Code・Codex、Herdrを用意する。
`cdr` を使う場合は fish、ghq、fzf も用意する。この端末では fzf を apt、ghq を Go で導入している。

```sh
sudo apt install fish fzf
go install github.com/x-motemen/ghq@v1.11.2
```

fish の設定は `~/go/bin` を `PATH` に追加する。
Herdrが未導入の場合は[公式のインストール手順](https://herdr.dev/docs/install/)に従う。

```sh
git clone git@github.com:tsukuneA1/dotfiles.git ~/dotfiles
cd ~/dotfiles
python3 scripts/install.py
```

設定を編集した後は、使用中のチェックアウトで次のコマンドを実行して再適用する。

```sh
python3 scripts/install.py
herdr server reload-config  # Herdrのサーバーが起動している場合
```

fish と bash の設定だけを適用する場合は `python3 scripts/install.py --shell-only` を使う。

Claude Code・Codexの変更と fish への切り替えは、新しいセッションから使う。

## 管理する設定

| ファイル | 内容 | 適用先 |
| --- | --- | --- |
| `claude/settings.json` | Opus（1M）、日本語、高いeffort、fullscreen、auto mode、既存のプラグイン設定 | `~/.claude/settings.json` にマージ |
| `codex/config.toml` | GPT-6.1 Sol、medium、Auto-review、workspace-write、Herdr用hooks | `~/.codex/config.toml` にマージ |
| `herdr/config.toml` | 作業ディレクトリの引き継ぎ、ペインのエージェント名、アプリ内通知、セッション復元 | `~/.config/herdr/config.toml` へシンボリックリンク |
| `fish/config.fish` | `cdr` で ghq のリポジトリを fzf から選択 | `~/.config/fish/config.fish` へシンボリックリンク |
| `bash/exec-fish.bash` | 対話 bash の初期化後に `exec fish` | `~/.bashrc` の末尾に管理ブロックを追加 |

Claude Codeは `permissions.defaultMode = "auto"`、Codexは `approval_policy = "on-request"` と `approvals_reviewer = "auto_review"` を使用する。
Claudeのauto modeの利用可否はアカウント・モデル・組織設定にも依存する。

Herdr連携フックは `herdr integration install claude` と `herdr integration install codex` で生成する。
端末ごとのパスやHerdrのバージョンに依存するので、生成されたフック自体はGitに保存しない。
既存のフックやプラグイン、Codexのプロジェクトごとの信頼設定は残す。

認証情報、APIキー、履歴、セッション、`settings.local.json`、MCP接続情報は管理対象外。
変更前のファイルは `~/.local/state/dotfiles/backups/日時/` に保存する。
戻す場合はバックアップを元の場所へコピーする。Herdrとfishの設定は先にシンボリックリンクを削除してからコピーする。

Herdr以外の設定だけを適用する場合や、別ディレクトリで試す場合：

```sh
python3 scripts/install.py --skip-integrations
python3 scripts/install.py --home /tmp/dotfiles-preview --skip-integrations
```

## Herdrの使い方

プロジェクトのディレクトリで `herdr` を起動し、ペイン内で `claude` または `codex` を実行する。
マウスや右クリックメニューでペインを操作できる。

キーボード操作は `Ctrl+b` を押して離してから、次のキーを押す。

| キー | 操作 |
| --- | --- |
| `v` | 右にペインを分割 |
| `-` | 下にペインを分割 |
| `c` | 新しいタブ |
| `q` | 切り離す（エージェントは動き続ける） |
| `?` | キー一覧 |

切り離した後は `herdr` で再接続する。Herdr内からの二重起動は避ける。

```sh
herdr status
herdr integration status
```

公式資料：[Claude Codeの権限モード](https://code.claude.com/docs/en/permission-modes)、[Codex設定](https://learn.chatgpt.com/docs/config-file/config-reference)、[Herdrガイド](https://herdr.dev/docs/)。
