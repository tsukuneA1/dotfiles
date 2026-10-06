# dotfiles

Claude Code、Codex、Herdrの共通設定。

## 適用

Python 3.11以上と、ログイン済みのClaude Code・Codex、Herdrを用意する。
Herdrが未導入の場合は[公式のインストール手順](https://herdr.dev/docs/install/)に従う。

```sh
git clone git@github.com:tsukuneA1/dotfiles.git ~/dotfiles
cd ~/dotfiles
python3 scripts/install.py
```

この端末では `~/dotfiles` に配置済みなので、設定を編集した後は次のコマンドで再適用する。

```sh
python3 ~/dotfiles/scripts/install.py
herdr server reload-config  # Herdrのサーバーが起動している場合
```

Claude Code・Codexの変更は、新しいセッションから使う。

## 管理する設定

| ファイル | 内容 | 適用先 |
| --- | --- | --- |
| `claude/settings.json` | Opus（1M）、日本語、高いeffort、fullscreen、auto mode、既存のプラグイン設定 | `~/.claude/settings.json` にマージ |
| `codex/config.toml` | GPT-6.1 Sol、medium、Auto-review、workspace-write、Herdr用hooks | `~/.codex/config.toml` にマージ |
| `herdr/config.toml` | 作業ディレクトリの引き継ぎ、ペインのエージェント名、アプリ内通知、セッション復元 | `~/.config/herdr/config.toml` へシンボリックリンク |

Claude Codeは `permissions.defaultMode = "auto"`、Codexは `approval_policy = "on-request"` と `approvals_reviewer = "auto_review"` を使用する。
Claudeのauto modeの利用可否はアカウント・モデル・組織設定にも依存する。

Herdr連携フックは `herdr integration install claude` と `herdr integration install codex` で生成する。
端末ごとのパスやHerdrのバージョンに依存するので、生成されたフック自体はGitに保存しない。
既存のフックやプラグイン、Codexのプロジェクトごとの信頼設定は残す。

認証情報、APIキー、履歴、セッション、`settings.local.json`、MCP接続情報は管理対象外。
変更前のファイルは `~/.local/state/dotfiles/backups/日時/` に保存する。
戻す場合はバックアップを元の場所へコピーする。Herdr設定は先にシンボリックリンクを削除してからコピーする。

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
