# md-readable.nvim

[English version](README.md)

このプラグインはmarkdownを読解することに長けたプラグインです。
原文と未保存の編集内容を保持しながら、別の読み取り専用画面でMarkdownを表示します。以下の機能を実装しています。SSGごとの対応範囲は[静的設定の対応表](tests/fixtures/navigation/SUPPORTED.md)を参照してください。

- Appearance
    - markdown構文ハイライト
    - テーブルレンダリング
    - コードブロック
    - 読書表示だけのカラーテーマ切り替え
    - テーブル内/URLの長文省略表示
    - ローカルリンク, 外部リンクごとのアイコン表示
- Navigation
    - ミニマップ
        - 原文に対応するGit差分・LSP診断の表示
    - 見出しツリー
    - Focus Mode
    - 主要SSGの目次・前後
        - mdBook, Docusaurus, MkDocs, Zensical, Astro/Starlight, HonKit, GitBook
- Formatting
    - テーブル整形
    - 表の行・列の明示的な挿入削除
- Contents
    - 画像表示(png,jpg,svg,webpなど)
    - Mermaidダイアグラムレンダリング
- Integration
    - Telescope / Snacksのpreview連携（pickerは任意依存）

一部Writingサポートもそなわっています。
- Writing
    - Read Buffer, Write Buffer のカーソル位置・ページ移動の双方向同期

読書表示の `/` は表示テキストを検索し、`y` は対応するMarkdown原文をコピーします。省略した内容を含めて原文全体を検索する専用コマンドも提供します。Neovim終了をまたぐ読書位置の保存は行いません。

リンクラベルの一部を選択するとその文字列、ラベル全体を選択すると元のMarkdownリンク全体をコピーします。

AGENTS.mdに記載したプラグインは参考実装であり、必須依存ではありません。描画・Focus・表編集・ミニマップを本体内に実装しています。

[合意済み仕様](docs/final-spec-review.md)、[全体追跡Issue](https://github.com/takeshiD/md-readable.nvim/issues/33)、[検証記録](docs/verification.md)を参照してください。

# Requirements
- Neovim >= 0.12
- 画像表示にはKitty graphics対応端末が必要です。WezTerm / Ghosttyを対象としていますが、端末での画像の目視確認は未実施です。
- 任意依存: 画像変換にImageMagick等、Mermaidに導入済みの`mmdc`、許可した外部画像の取得に`curl`、Git差分に`git`。
- Telescope / Snacksは連携を利用する場合だけ必要です。ツールを自動インストールすることはありません。

# 使い方

プラグインマネージャーでこのリポジトリを読み込みます。実装ブランチを使うlazy.nvimの例:

```lua
{
  "takeshiD/md-readable.nvim",
  branch = "feat/readable-implementation",
  opts = {},
}
```

Markdownを開いて実行します。

```vim
:MdReadable          " 同じウィンドウを読書表示にする
:MdReadable vert     " 左に原文、右に読書表示
:MdReadable float    " floatingで読書表示
:MdReadable source   " 対応する原文の位置へ戻る
:MdReadable close
```

setupは任意です。コマンドを好みのキーやautocmdへ割り当ててください。グローバルキーマップは追加しません。読書bufferの`y`は原文をコピーし、Ctrl-O / Ctrl-Iは原文のジャンプ履歴をたどります。`/`・`?`・`n`・`N`は表示テキストを検索します。

| `MdReadable`の後に続ける操作 | 内容 |
| --- | --- |
| `nav` / `outline` / `select` | 書籍目次、ページ見出し、adapter・treeの選択 |
| `prev` / `next` / `heading-prev` / `heading-next` | 章・見出し移動 |
| `links` / `open` | リンク一覧、カーソル位置のリンク・セルを開く |
| `search [pattern]` | 省略した内容を含む原文検索 |
| `focus on/off/toggle` | 段落Focus。Visual範囲を指定して起動すると行範囲を固定 |
| `theme default/dark/light` | 読書表示だけの配色変更 |
| `minimap on/off/toggle/focus` | ミニマップ。Enterで本文へ移動 |
| `table format` | 原文の表を明示的に整列 |
| `table row-before/row-after/row-delete [count]` | データ行の挿入・削除 |
| `table col-before/col-after/col-delete [count]` | 列の挿入・削除 |
| `expand` / `tab [index]` | 省略内容の展開、静的タブの選択 |
| `images allow/deny` | この読書Sessionでの外部画像取得の許可・禁止 |
| `refresh` / `diagnostics` | 構造の再取得、ナビゲーション・画像エラーの確認 |

表編集はundoで戻せ、自動保存しません。装飾だけをコピーした場合はレジスタを変更しません。省略セルの`…`を含めてコピーすると、元のセル全体を取得します。

# 設定

```lua
require("md-readable").setup({
  layout = "integrated", -- integrated / separate / ondemand
  width = 100,
  keymaps = false, -- trueなら読書bufferにqとEnterを追加
  table = { max_cell_width = 28 },
  focus = { coefficient = 0.5, span = 0 },
  minimap = { width = 14, mode = "braille", git = true, diagnostic = true },
  images = { enabled = true, remote = false, height = 10 },
  mermaid = { command = "mmdc" },
  -- adapters = { adapter = "mdbook", root_dir = "/path/to/book" },
})
```

狭い画面では本文幅を優先し、目次をfloatingで選択できます。Nerd Fontは不要で、ミニマップには`mode = "ascii"`もあります。Git差分はindexと未保存編集を含む原文を比較し、LSP診断はNeovim標準の診断情報から取得します。

動的なSSG設定は実行しません。必要に応じてLua / JSONの共通ナビゲーションproviderを指定できます。詳細は`:help md-readable-providers`と[SSG対応表](tests/fixtures/navigation/SUPPORTED.md)を参照してください。

# picker連携

```lua
local previewer = require("md-readable.integrations.telescope").previewer()
require("telescope.builtin").find_files({ previewer = previewer })

require("snacks").setup({
  picker = { preview = require("md-readable.integrations.snacks").preview() },
})
```

`:Telescope md_readable find_files` / `:Telescope md_readable live_grep`も利用できます。選択確定の動作はpicker側に任せ、非対応ファイルは標準previewへ戻します。詳細は`:help md-readable`、依存状況は`:checkhealth md-readable`で確認できます。

# 開発・検証

```sh
nvim --headless -n -u NONE -i NONE -l tests/run.lua
```

解析、7SSG、実際の読書Session、原文コピー、同期、狭幅UI、表編集、Git/LSP、画像プロトコル・取消し、導入済みpickerとの連携を検証します。実端末の画像と実際のmmdcの確認状況は[検証記録](docs/verification.md)に記載しています。

# License
MIT
