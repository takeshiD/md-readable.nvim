# md-readable.nvim

[English version](README.md)

このプラグインはmarkdownを読解することに長けたプラグインです。
以下は必ず実装する目標機能です。現在は未実装で、[設計書](md-readable_design.md)で要件を整理しています。

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
        - 必須対応SSG: mdBook, Docusaurus, MkDocs, Zensical, Astro, HonKit, GitBook
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

AGENTS.mdに記載したプラグインは参考実装であり、必須依存にしません。必要な同等機能を本プラグイン内に実装します。

[最終仕様確認案](docs/final-spec-review.md)と[並列実装計画](docs/implementation-issues.md)を参照してください。

# Requirements
- Neovim >= 0.12
- (Optional) 画像表示: WezTerm, Ghosttyを対象とし、実装後に動作検証します
- (Optional) Mermaid: mermaid-cli, Mermaid

# License
MIT
