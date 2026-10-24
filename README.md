# dotfiles

Claude Code、Codex、Herdr、fish、Neovim の共通設定。

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

## ターミナルで Web ページを読む

fish の `wr`（`webread` の略）は AtCoder の問題文と GitHub のリポジトリ・Issue・PR・ファイルに対応する。`w3m` と `gh` が必要。

```fish
wr 300 a             # ABC 300 A
wr abc300 c          # 同じく ABC 300 C
wr edpc a            # Educational DP A
wr z                 # Educational DP Z
wr --lang en 300 a   # 英語の問題文
wr -e 300 a          # ABC 300 A の解説
wr -e edpc a         # Educational DP A の解説
wr -E 300 a          # 解説が複数ある場合の一覧
wr --dump 300 a      # 端末へテキストとして出力
wr 'https://github.com/cli/cli'
wr --comments 'https://github.com/cli/cli/issues/1'
wr 'https://github.com/cli/cli/blob/trunk/docs/README.md'
```

AtCoder は選んだ言語の問題文だけを `w3m` で開き、`\(...\)`、`$...$`、単独の `\dots`・`\vdots` や `A_i`・`A_{N-1}` などを端末向けの文字に変換する。入力形式中の数式も変換し、サンプル入出力は元の文字を保つ。複雑な数式は一行の表記になり、未対応の TeX コマンドはそのまま残す。`-e` は問題別の解説一覧から公式解説を優先して本文を開き、記事を取得できない場合はリンク一覧を表示する。`-E` は最初からリンク一覧を開く。閲覧画面では `q` で確認なしに終了でき、マウスで端末のテキスト選択・コピーができる。`--dump` を付けると標準出力に表示できる。GitHub のリポジトリ・Issue・PR は `gh` の表示を使い、ファイルは Markdown なら `glow` がインストール済みの場合に限り `glow` で開く。ファイル URL のブランチ名に `/` が入る場合は未対応。

```sh
sudo apt install w3m gh
```

## 管理する設定

| ファイル | 内容 | 適用先 |
| --- | --- | --- |
| `claude/settings.json` | Opus（1M）、日本語、高いeffort、fullscreen、auto mode、既存のプラグイン設定 | `~/.claude/settings.json` にマージ |
| `codex/config.toml` | GPT-6.1 Sol、medium、Auto-review、workspace-write、Herdr用hooks | `~/.codex/config.toml` にマージ |
| `herdr/config.toml` | 作業ディレクトリの引き継ぎ、ペインのエージェント名、アプリ内通知、セッション復元 | `~/.config/herdr/config.toml` へシンボリックリンク |
| `fish/config.fish` | `c` で直下のディレクトリを fzf 選択、`c ..` などの引数付き移動、`cdr` で ghq リポジトリ選択、`wr` で AtCoder/GitHub を表示 | `~/.config/fish/config.fish` へシンボリックリンク |
| `nvim/init.lua` | netrw のツリー表示と `:cd` 後の表示更新、ファイルを開いたときの作業ディレクトリ追従、PDF を xpdf で表示、Git の変更表示、Python スニペットと単語の候補表示、Enter での確定・展開、`:cd<Tab>` でディレクトリを fzf 選択、`-` で netrw を開く、`Space y` でファイル全体をコピー | `~/.config/nvim/init.lua` へシンボリックリンク |
| `nvim/snippets/python.json` | Python 用スニペット | `~/.config/nvim/snippets/python.json` へシンボリックリンク |
| `bash/exec-fish.bash` | `c` で直下のディレクトリを fzf 選択、引数付き移動、対話 bash から `exec fish` | `~/.bashrc` の末尾に管理ブロックを追加 |

Neovim では `:cd<Tab>` でカレントディレクトリ以下を選び、`:cd hoge/<Tab>` で `hoge/` 以下を選べる。候補は 6 階層まで表示し、選択するとそのディレクトリへ移動する。
`:cd<Tab>` の候補にはフォルダーアイコンを表示する。netrw の一覧では左端にフォルダーや拡張子に応じたファイルアイコンを表示する。アイコンには [Nerd Fonts](https://www.nerdfonts.com/font-downloads) の記号を使うため、**画面を描画する端末のフォント**に Nerd Font を指定する必要がある。WSL の Ubuntu を Windows Terminal で開いている場合は、Windows 側で Nerd Font を「すべてのユーザーに対してインストール」し、Windows Terminal のフォント フェイスで選ぶ。この PC では全プロファイル共通で `0xProto Nerd Font Mono` を指定している。Ubuntu 内の `~/.local/share/fonts` に入れるだけでは Windows Terminal の表示は変わらない。
`nvim .` のディレクトリ一覧はツリー表示になり、ディレクトリ上で Enter を押すと `:pwd` を変えずにその場で展開・折りたたみできる。ファイルを開いた場合はそのファイルのディレクトリに移る。
`:cd` や `:cd<Tab>` で移動すると、表示中のツリーの起点も移動先に切り替わる。
ノーマルモードで `Space y` を押すと、ファイル全体をシステムクリップボードにコピーする。
ノーマルモードで `-` を押すと netrw に戻る。Git 管理下のファイルでは、左端に追加 `+`、変更 `~`、削除 `_` を表示する。netrw では変更ファイルに `M` などの状態を表示し、変更を含むディレクトリに `●` を表示する。
ホームディレクトリの Git 表示は省略する。ホーム全体の変更確認による起動時の遅延を防ぐため、他のディレクトリの Git 表示も一覧が開いた後にまとめて更新する。
PDF を開くと Linux 側の `xpdf` ウィンドウでページを表示する。netrw から開いた場合は一覧に戻り、PDF を直接指定して起動した場合はそのディレクトリの一覧を開く。PDF の閲覧には `xpdf` が必要。

Claude Codeは `permissions.defaultMode = "auto"`、Codexは `approval_policy = "on-request"` と `approvals_reviewer = "auto_review"` を使用する。
Claudeのauto modeの利用可否はアカウント・モデル・組織設定にも依存する。

Herdr連携フックは `herdr integration install claude` と `herdr integration install codex` で生成する。
端末ごとのパスやHerdrのバージョンに依存するので、生成されたフック自体はGitに保存しない。
既存のフックやプラグイン、Codexのプロジェクトごとの信頼設定は残す。

認証情報、APIキー、履歴、セッション、`settings.local.json`、MCP接続情報は管理対象外。
変更前のファイルは `~/.local/state/dotfiles/backups/日時/` に保存する。
戻す場合はバックアップを元の場所へコピーする。Herdr、fish、Neovimの設定は先にシンボリックリンクを削除してからコピーする。

Herdr以外の設定だけを適用する場合や、別ディレクトリで試す場合：

```sh
python3 scripts/install.py --skip-integrations
python3 scripts/install.py --home /tmp/dotfiles-preview --skip-integrations
```

## Herdrの使い方

プロジェクトのディレクトリで `herdr` を起動し、ペイン内で `claude` または `codex` を実行する。
マウスや右クリックメニューでペインを操作できる。

キーボード操作は `Ctrl+a` を押して離してから、次のキーを押す。

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
