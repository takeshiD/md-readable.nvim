# [TRACK] md-readable.nvim 全機能の並列実装

## 目的と完了条件

他人のMarkdownとSSG文書を、画像・図を含む完成した文書に近い表示で読むNeovimプラグインを実装する。以下32件はすべて必須であり、一部の段階が終わった時点では全体完了としない。

標準検索は表示テキスト、標準yankは原文。原文・読書表示のカーソルとページ移動を双方向同期し、Focusと配色は読書表示だけに適用する。参考4プラグインの対象機能を内蔵し、SSG全7対象、画像/Mermaid、表整形/行列編集、ミニマップ/Git/LSP、Telescope/Snacks連携まで接続する。

## 実装Issue

- [ ] [I00: 共通契約・headlessテスト基盤](https://github.com/takeshiD/md-readable.nvim/issues/1)
- [ ] [I01: Markdown構造の抽出](https://github.com/takeshiD/md-readable.nvim/issues/2)
- [ ] [I02: 原文と表示の範囲対応](https://github.com/takeshiD/md-readable.nvim/issues/3)
- [ ] [I03: 基本読書レンダリング](https://github.com/takeshiD/md-readable.nvim/issues/4)
- [ ] [I04: ナビゲーション共通モデル](https://github.com/takeshiD/md-readable.nvim/issues/5)
- [ ] [I05: 宣言的設定の解析](https://github.com/takeshiD/md-readable.nvim/issues/6)
- [ ] [I06: SUMMARY構文の解析](https://github.com/takeshiD/md-readable.nvim/issues/7)
- [ ] [I07: プロジェクト検出と拡張入力](https://github.com/takeshiD/md-readable.nvim/issues/8)
- [ ] [I08: mdBook対応](https://github.com/takeshiD/md-readable.nvim/issues/9)
- [ ] [I09: HonKit対応](https://github.com/takeshiD/md-readable.nvim/issues/10)
- [ ] [I10: GitBook対応](https://github.com/takeshiD/md-readable.nvim/issues/11)
- [ ] [I11: MkDocs対応](https://github.com/takeshiD/md-readable.nvim/issues/12)
- [ ] [I12: Zensical対応](https://github.com/takeshiD/md-readable.nvim/issues/13)
- [ ] [I13: Docusaurus対応](https://github.com/takeshiD/md-readable.nvim/issues/14)
- [ ] [I14: Astro/Starlight対応](https://github.com/takeshiD/md-readable.nvim/issues/15)
- [ ] [I15: 読書Sessionと原文同期](https://github.com/takeshiD/md-readable.nvim/issues/16)
- [ ] [I16: 目次・見出し・前後ページUI](https://github.com/takeshiD/md-readable.nvim/issues/17)
- [ ] [I17: 表の表示と省略内容の確認](https://github.com/takeshiD/md-readable.nvim/issues/18)
- [ ] [I18: 表の原文整形](https://github.com/takeshiD/md-readable.nvim/issues/19)
- [ ] [I19: 原文コピーと原文検索](https://github.com/takeshiD/md-readable.nvim/issues/20)
- [ ] [I20: Focus Mode](https://github.com/takeshiD/md-readable.nvim/issues/21)
- [ ] [I21: 読書表示のテーマ](https://github.com/takeshiD/md-readable.nvim/issues/22)
- [ ] [I22: 画像の本文内表示](https://github.com/takeshiD/md-readable.nvim/issues/23)
- [ ] [I23: Mermaid描画](https://github.com/takeshiD/md-readable.nvim/issues/24)
- [ ] [I24: ミニマップ](https://github.com/takeshiD/md-readable.nvim/issues/25)
- [ ] [I25: 一般的な拡張記法](https://github.com/takeshiD/md-readable.nvim/issues/26)
- [ ] [I26: リンク一覧とリンク操作](https://github.com/takeshiD/md-readable.nvim/issues/27)
- [ ] [I27: 全体接続・導入・品質確認](https://github.com/takeshiD/md-readable.nvim/issues/28)
- [ ] [I28: Telescope / Snacks連携](https://github.com/takeshiD/md-readable.nvim/issues/29)
- [ ] [I29: 表の行列挿入削除](https://github.com/takeshiD/md-readable.nvim/issues/30)
- [ ] [I30: ミニマップのGit差分](https://github.com/takeshiD/md-readable.nvim/issues/31)
- [ ] [I31: ミニマップのLSP診断](https://github.com/takeshiD/md-readable.nvim/issues/32)

## 並列実装の進め方

I00を先に確定し、文書解析・SourceMap・ナビゲーション/各parserから並列化する。各Issueの先行リンクが依存関係を表す。SSGアダプターやFocus/表/テーマ/画像は契約fixtureを使い独立に進める。I27が共有の公開入口・config・コマンド・README/helpを管理し、接続を逐次進める。

各エージェントは独立worktreeを使い、担当モジュールと専用テストを編集する。先行Issueの統合前に自分の契約だけで結合完了としない。共通契約の変更は統合担当が調整する。

## 仕様と確認

- `md-readable_design.md`: 機能・共通モデル・動作の仕様。
- `docs/final-spec-review.md`: Q1〜Q21からまとめた仕様と初期値。
- `docs/implementation-issues.md`: 担当境界と依存関係。
- `docs/adr/`: 原文コピー/表示検索の分離と、参考機能の内蔵方針。

各機能のheadless検証、全7対象の対応形式表、WezTerm/Ghostty等の実表示結果、README/help/health/導入例を揃える。画像等の任意依存がない環境でも基本表示・ナビゲーションが成立すること、原文を読むだけでは変更しないこと、未保存内容を保持することを確認する。Neovim終了をまたぐ位置保存、動画・PlantUML・CSV変換・数式は対象外。
