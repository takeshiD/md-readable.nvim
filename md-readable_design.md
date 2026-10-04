# Neovim Markdown Reader 設計書

作成日: 2026-09-29  
状態: 合意済み・実装中（2026-10-03、Q22承認）  
対象: 並列実装を担当するCodexエージェント / 開発者  
名称: md-readable.nvim（README・リポジトリ名に統一）。本書に残る `reader` / `Reader*` は従来案の仮名であり、公開Luaモジュールは `md-readable`、コマンドの入口は `MdReadable` とする。

## 0. 本書の読み方

本書はREADMEの必須機能とgrill-with-docsのQ1〜Q21の回答を統合し、Q22で承認された仕様である。[対話の合意記録](docs/design-decisions.md)、[並列実装Issue一覧](docs/implementation-issues.md)、[合意した初期値](docs/final-spec-review.md)を併せて参照する。実装Issueは[全体追跡 #33](https://github.com/takeshiD/md-readable.nvim/issues/33)に登録済み。

実装必須なのは、全Appearance / Navigation / Formatting / Contents / Writing機能とSSG全7対象、およびQ20で追加されたpicker連携・表の行列編集・Git/LSP注釈である。段階分けは実装順序を表し、後続機能を任意扱いしない。任意依存の導入と、機能自体を実装する義務は区別する。

ユーザーが明示的に不要としたNeovim終了をまたぐ読書位置保存は対象外。参考プラグインを丸ごと再現する約束ではなく、ここで列挙した機能を内蔵実装する。動画・PlantUML・CSV変換・数式計算は今回の追加範囲に含めない。一般的な拡張記法の見た目は、初期実装を確認してから調整する。

## 1. 目的と設計思想

Neovim上で、他人のMarkdownとSSGの書籍・ドキュメントを、完成した文書に近い表示で読み、構造に沿って移動できるプラグインを作る。原文の確認や編集への移行も支援する。

Markdownに「必要な情報の強調」「不要な情報の抑制」「構造に沿った移動」を提供する。表示上の配置変更、画像・図を含む文書としての読みやすさを重視する。注意書き・折りたたみ・タブなど一般的な拡張表現も扱い、サイト独自のコンポーネントは原文を確認できるようにする。具体的な記法と見た目は初期実装を基に見直す。

本文の意味や位置関係を保ち、見出し、段落、表、コード、リンクの違いを把握しやすくする。対応環境では、画面内に入った画像・Mermaidを本文内に自動表示する。

### 1.1 制約

- ターミナル版Neovimを第一の対象とする。
- UIは等幅セル、通常のハイライト、分割ウィンドウ、floating window、winbar / statuslineなどで成立させる。
- 見出しだけのフォント拡大、比例フォント、CSSカード、影などを必須にしない。
- OSC 66、画像プロトコル、特定ターミナル、Nerd Fontを基本機能の必須条件にしない。
- 読むだけで元のファイルを変更しない。
- ローカル文書だけで基本機能を利用でき、クラウドアカウントを要求しない。
- 通常の移動、検索、ジャンプ履歴、既存キーマップ、カラースキームとの共存を重視する。

## 2. 必須要件と初期設定

### 2.1 ユーザーから挙がった要件

| 領域 | 要件 |
| --- | --- |
| 構造の可視化 | 見出し・段落を区別しやすいこと |
| 集中 | limelight.vimと同じ動作を基準に、読む範囲を強調する |
| 配色 | 読書表示だけのカラーテーマ切り替え |
| 表 | 列が崩れず、長い表を読みやすくする |
| コード | コードブロックの言語に応じたハイライト |
| ナビゲーション | 書籍・サイトの目次、前後ページ、ページ内見出しへの移動 |
| リンク | 文書中リンクの一覧と、ローカル・外部の識別 |
| 読む・書く | 読むbufferと書くbufferを分離し、位置を同期する。左右分割・floatingで確認できる |
| 省略 | 長いURL・表などを省略表示し、必要時に元の内容を確認できる |
| 整形・表編集 | 表の整列と行・列の挿入削除を、明示操作として扱える |
| 図・画像 | Mermaid等の描画、画像表示 |
| 俯瞰 | 見出しツリーとミニマップの両方を提供し、現在地・Git差分・LSP診断が分かる |
| picker連携 | Telescope / Snacksのpreviewで読書描画を利用できる |

最終的なナビゲーション対応対象は **mdBook / Docusaurus / MkDocs / Zensical / Astro / HonKit / GitBook** の7つとする。

確定したアーキテクチャ方針は、**共通の構造化モデルをナビゲーションUIの入力とし、各SSGのアダプターがそのモデルを出力する**ことである。

### 2.2 導入条件と初期設定

| 項目 | 方針 |
| --- | --- |
| 製品名・公開入口 | md-readable.nvim、Luaは`md-readable`、コマンドは`MdReadable` |
| 最低Neovimバージョン | READMEに合わせてNeovim >= 0.12 |
| 読むbuffer | 原文とは別の読み取り専用派生buffer。行・byte列・要素範囲の対応を保持 |
| UI配置 | configで3配置を選択可能。既定は左側の統合ツリー |
| ミニマップ | 内蔵の縮小表示。既定は非表示、操作で開閉。Git差分・LSP診断を表示 |
| テーマ・Focus | 読書表示だけに適用。原文や他のwindowへ波及させない |
| 読書位置保存 | 同一Neovimセッション内の状態保持のみ。終了をまたぐ保存はしない |
| 基本操作 | コマンドを提供し、ユーザーがキーマップ・自動実行へ割り当てる |
| 任意依存 | 画像変換・Mermaid・Git注釈・picker等は利用可能な環境で有効化。4参考プラグインは必須依存にしない |

引数なし・再実行・終了時の動作、初期拡張記法、Git比較基準などの具体的な初期値は[最終確認事項](docs/final-spec-review.md)にまとめる。合意後はその内容も仕様として扱う。

## 3. 実装範囲と進め方

共通契約を先に確定し、読書表示・文書構造・ナビゲーション・各SSGを並列に実装する。最初の統合確認は、単一Markdownの読書表示とmdBookの章移動をつなぎ、原文無変更・未保存内容保持・同期・検索・コピーを実際に操作できる状態とする。

この統合確認は中間地点であり、全7対象、画像・Mermaid、Focus、表編集、ミニマップ、picker連携まで揃って完成とする。Issueの分割・担当ファイル・先行関係は[実装Issue一覧](docs/implementation-issues.md)に定義する。

### 3.1 SSG対応の完成条件

7対象それぞれについて「検出」「対応する設定構文」「非対応構文」「fixture」「実際に開ける文書への対応付け」を揃える。名前だけのアダプターや、常にディレクトリ順へ置き換える実装は対応完了としない。ローカル文書と静的設定を標準対応とし、動的生成結果は明示provider経由で受け取る。

## 4. アーキテクチャ

| 層 | 責務 | 知ってはいけないこと |
| --- | --- | --- |
| SSG adapter | 検出、設定解釈、章順・階層・タイトル・ローカル文書への解決 | Neovimウィンドウの配置 |
| Navigation core | モデル検証、索引、現在ノード、親、前後ページ | SSG固有の設定キー |
| Document structure | 開いている文書の見出し・リンク・ブロックとソース範囲 | 書籍全体の並び順 |
| Session | 対象文書ウィンドウ、選択中ツリー、読書位置、展開状態 | SSGパーサーの実装詳細 |
| UI | 目次、見出し、前後ページ、picker、強調表示 | SUMMARY.mdやYAML等の解析 |
| Reader projection | 元bufferから読むbufferへの投影、位置対応、省略 | SSG検出 |
| Optional providers | formatter、画像、Mermaid、独自ナビゲーション | UIの必須依存 |

データの流れ:

```text
プロジェクト設定・文書 → SSG adapter → NavigationSnapshot → Navigation core → UI
元の文書buffer       → Document structure → Outline / Links / Blocks → UI
元の文書buffer       → Reader projection → 読むbuffer + SourceMap
```

見出しツリーをサイドバーに埋め込んでも、書籍の章ツリーに書き戻さない。ページ内見出しの展開によって前後ページの順序が変わってはいけない。

## 5. 共通ナビゲーションモデル

以下のTypeScriptは言語非依存の契約を説明するための記法である。プラグイン本体はLuaで実装し、LuaLSの型注釈を付けたtableで同等の構造を表す。クラス継承は必須にしない。

```ts
type NavTarget =
  | { type: "document"; path: string; anchor?: string }
  | { type: "external"; url: string }
  | { type: "unavailable"; raw: string; reason: string };

interface SourceLocation {
  path: string;          // 設定・目次のファイル。rootDir相対
  row?: number;         // 0-based
  byteColumn?: number;  // 0-based UTF-8 byte offset
}

interface NavigationNode {
  id: string;               // tree内の出現位置を識別。文書パスとは別
  title: string;
  target?: NavTarget;       // 省略時はカテゴリ等の移動先を持たない項目
  children: NavigationNode[];
  source?: SourceLocation;
}

interface NavigationTree {
  id: string;
  title: string;
  items: NavigationNode[];  // 確定済みの表示順・読む順序
}

interface Diagnostic {
  severity: "info" | "warning" | "error";
  code: string;
  message: string;
  nodeId?: string;
  source?: SourceLocation;
}

interface NavigationSnapshot {
  schemaVersion: 1;
  rootDir: string;          // プロジェクトの絶対パス
  adapterId: string;
  trees: NavigationTree[];  // 通常は1件。複数sidebar / Spaceにも対応
  orderOrigin: "declared" | "generated" | "inferred" | "custom";
  diagnostics: Diagnostic[];
}
```

### 5.1 モデルの契約

- `target`と`children`は独立している。本文を持つ章の入口に子ページがあってよい。
- `items` / `children` の配列順をcoreやUIが再ソートしない。
- `document.path` は `rootDir` 相対の正規化済みローカルパス。`docs_dir`等のSSG固有の基準はadapterが解決済みとする。
- 通常は区切りを `/` に統一し、ファイルI/O直前にOSパスへ変換する。大文字小文字を一律に小文字化しない。
- 文書外の参照が必要なら相対 `..` を保持できる。アクセス可否と存在確認はresolverで判定し、黙って別ファイルへ付け替えない。
- anchorはパスから分離する。URLのクエリをファイル名として扱わない。
- `id` は同一ツリー内の出現に対して一意とする。同じ文書への複数参照をcoreが表現できるようにする。各SSGで許されるかはadapterが検証する。
- IDは無関係な本文編集で変化させない。設定の明示IDを優先し、それがなければツリーの論理的な位置・ターゲット等から生成する。表示行番号だけをIDにしない。
- draft、生成されたカテゴリページ、未解決のターゲットは必要に応じ `unavailable` として表示する。架空のローカルファイルを作らない。
- `orderOrigin` は順序の根拠を表す。プロジェクト検出の確信度とは別の概念である。
- 0件の正常な目次、未対応の構文、解析失敗を区別する。
- Snapshotは公開後に直接変更しない。再解析で新しいSnapshotへ置き換える。

### 5.2 共通処理

coreは以下を提供する。

- `validate(snapshot)`：必須値、ID重複、循環、ターゲットの型を検証。
- `index(tree)`：ノードID、親、文書パスからノード出現への索引を作成。
- `resolve_current(path, context)`：現在文書と選択中ツリーから現在ノードを決定。
- `breadcrumbs(node_id)`：祖先から現在ノードまでを取得。
- `reading_order(tree)`：深さ優先・親を先にたどり、documentターゲットを並べる。
- `previous(node_id)` / `next(node_id)`：選択中ツリー内で移動先を返す。

前後移動の既定ルール:

1. 本文を持つ親ページを訪問した後、子ページへ進む。
2. カテゴリ、外部リンク、unavailableは読み順から除外する。
3. 不在ファイルは診断を残し、移動対象から除外する。UIでは消さず無効表示する。
4. 同じファイルが複数出現する場合も、ツリー上の出現位置を保持する。
5. 文書を直接開いた際に候補が複数ある場合、同じセッションの選択履歴を優先し、それでも決まらなければ選択中ツリーの最初の出現を採用する。
6. 先頭・末尾で循環しない。移動不可を控えめに示す。
7. 目次に含まれない文書では見出しナビは有効、前後ページは無効とする。
8. 初期実装はツリー順を採用する。SSG独自の前後ページ上書きは後続対応とし、検出時に差異を診断する。

## 6. アダプター契約と検出

概念的なLuaインターフェース:

```lua
---@class ReaderAdapter
---@field id string
---@field detect fun(ctx: ReaderDetectContext): ReaderCandidate[]
---@field parse fun(ctx: ReaderParseContext, done: fun(result: ReaderParseResult)): ReaderCancel

-- Candidate: root_dir, adapter_id, config_path?, evidence[], priority
-- ParseResult:
--   { status = "ok" | "partial", snapshot = ..., dependencies = ... }
--   { status = "unsupported" | "error", diagnostics = ... }
-- ReaderCancel: function()。完了済みでも安全に呼び出せる。
```

`ctx`は対象ルート、設定の明示指定、ファイル読み取り、キャッシュ等を提供する。元ファイルを編集中の場合、同じパスのロード済みbuffer内容をディスクより優先できる読み取り境界を設ける。

`dependencies`には参照した設定・目次・frontmatter・ディレクトリ一覧を記録し、更新判定に使う。

### 6.1 検出ルール

1. ユーザーが明示したadapter / root / providerを最優先する。
2. 対象文書から親へ探索し、最も近い候補ルートを優先する。探索上限と明示rootを設定可能にする。
3. `SUMMARY.md`だけではmdBook / HonKit / GitBookを断定しない。共通のsummary候補として扱う。
4. `mkdocs.yml`だけではMkDocsとZensicalの実行主体を断定しない。共通のnav形式として扱い、必要なら明示設定で区別する。
5. 複数候補が同じルートに残れば、選択機能と候補の根拠を提供する。毎回ダイアログを出さずセッション中は選択を保持する。
6. 部分対応や解析失敗を、成功したディレクトリ推定に見せかけない。

### 6.2 SSG別対応方針

次の「実装範囲」は本プラグインの目標であり、各SSGの全仕様への互換性を宣言するものではない。

| 対象 | 主な入力 | 実装する範囲 | 差異・非対応を扱う方針 |
| --- | --- | --- | --- |
| mdBook | `book.toml`、ソースディレクトリの `SUMMARY.md` | 章順、ネスト、部タイトル、前書き・後書き、draft、設定されたソースルート | draftは移動不可。preprocessorが追加する構造は初期対象外。[S1] |
| HonKit | `book.json`等の設定、指定されたsummary | root、summary位置、ネストした章 | まず静的JSON設定。実行可能な設定・pluginの生成結果は独自providerで取り込む。[S2] |
| GitBook | `gitbook-docs.yaml`、Spaceの `.gitbook.yaml`、`SUMMARY.md` | ローカルSpaceの対応付け、root、summary位置、ページグループ、ネスト | 同期されていないSpaceは利用不可と示す。クラウドだけにある文書は取得しない。[S3] |
| MkDocs | `mkdocs.yml` / 明示された設定 | `docs_dir`、明示 `nav` の順序・ネスト・外部リンク | plugin、独自YAMLタグ、継承等は対応範囲を列挙。未対応ならpartial / unsupported。[S4] |
| Zensical | `zensical.toml` または `mkdocs.yml` | `[project].nav` / YAML nav、文書ルート、ネスト・外部リンク | MkDocsと共通部分を再利用するが、仕様差をadapterに閉じ込める。[S5] |
| Docusaurus | docs設定、`sidebars.js/ts`、frontmatter、カテゴリmetadata | 静的sidebarとautogenerated、文書ID→ローカルファイル、複数sidebar | JS/TSの任意実行に依存しない。静的解析できる構文を明示し、動的生成は独自providerへ。[S6] |
| Astro | Starlight設定、ローカル文書、独自provider | Starlightの明示sidebar・autogenerate・順序metadata。一般Astroは明示providerから取り込む | Astro全体に共通の書籍順序があると仮定しない。任意のloaderが返す遠隔コンテンツは初期対象外。[S7][S8] |

### 6.3 各形式の重要な扱い

- SUMMARY系は基礎パーサーを共有できるが、部タイトル・リンクタイトル・draft等の意味はadapter別に処理する。
- YAML/TOMLは専用のパーサーを使う。正規表現だけでネスト構造を解釈しない。navの順序を失うtable走査も避ける。
- DocusaurusはURLやslugをそのまま文書パスとみなさない。明示sidebarの文書ID、frontmatter、番号接頭辞、カテゴリ順序の対応fixtureを用意する。
- Docusaurusのversion / locale / docs instanceを、同じ読み順に混在させない。初期対応しないケースは検出して明示する。
- GitBookの複数Spaceは別treeとして表す。サイト全体のsection構造を保つ必要があれば、後続でtree選択用の階層を追加する。
- AstroのMarkdown / MDXはローカルに存在するものを扱う。MDXのJavaScriptやコンポーネントは実行せず、解釈できるMarkdown構造だけを使用する。
- `nav`やsummaryがない場合の自動生成順を、そのSSGと同じだと推測で宣言しない。検証済みアルゴリズムか `inferred` の明示が必要。
- 番号付きファイルを自然順で並べるfallback adapterは別機能とする。既存の明示目次を置き換えない。

### 6.4 動的設定と拡張入力

基本動作ではリポジトリ内のJavaScript / TypeScript / Python設定を自動実行しない。静的解析できない設定には、その式がある場所と不足する機能を診断する。

任意のSSGや独自Astroサイト向けに、以下を提供する。

- Neovim設定に登録するLua provider: `root_dir`を受け取り共通Snapshotを返す。
- 共通モデルのJSONファイルの明示読み込み。
- 後続拡張として、ユーザーが明示したコマンドのJSON出力読み込み。必要になるまで常駐プロセスや専用プロトコルは作らない。

静的設定を解析するためだけに、すべてのユーザーへNode.jsやPythonを必須にしない。必要なパーサー・依存の選定はローカル実装時に行い、ライセンス、対応構文、導入方法を記録する。

## 7. ページ内構造とリンク

### 7.1 見出しモデル

```ts
interface SourceRange {
  start: { row: number; byteColumn: number };
  end: { row: number; byteColumn: number }; // half-open
}

interface Heading {
  id: string;
  title: string;
  level: number;
  range: SourceRange;       // 見出しそのもの
  sectionRange: SourceRange;
  children: Heading[];
}

interface DocumentOutline {
  path: string;
  changedtick: number;
  items: Heading[];
}
```

- 位置は0-based行・UTF-8 byte列に統一。UI表示の行番号だけ1-basedにする。
- 日本語の表示セル幅とbyte列を混同しない。
- ATX見出しとSetext見出しを対象とする。fenced code内の `#` やfrontmatterを見出しにしない。
- Tree-sitterを利用する場合、parserの有無を確認する。ない場合は正確性を保てるfallbackか機能低下の明示を行う。
- ページ内移動はソース範囲を使い、slugから行を逆算しない。
- リンクのanchor解決にはSSGごとのslug規則・明示IDの違いがあるため、resolverを拡張可能にする。不明なanchorへ適当な行を返さない。
- 現在見出しはカーソルを含む最も深いsectionとする。先頭見出しより前ではページ自体を現在地とする。
- 見出し抽出は元bufferを使い、読むbufferの省略・整形結果を再解析しない。
- 編集後はchangedtick等で古い位置を検出し、再解析後にジャンプする。

### 7.2 文書中リンク一覧

リンク文字列、種別、解決済みターゲット、ソース範囲を保持する。inline linkに加えreference-style linkも解決する。

種別は少なくとも `local document` / `same-page anchor` / `external URL` / `asset` / `unresolved` を区別する。行末に種別を短く表示し、色だけに依存しない。外部URLやassetは前後ページの読み順に混ぜない。

## 8. ナビゲーションUI

coreを共用し、3種類のUI配置をconfigで切り替えられる設計にする。既定はツリー統合とし、ミニマップは非表示から操作で開閉する。すべての案で以下を満たす。

- 書籍の目次とページ内見出しが区別できる。
- 現在ページと現在見出しを表示する。
- 項目を選んだときだけ文書を移動する。選択カーソルの移動だけで読み位置を変更しない。
- 目次操作後は元の文書ウィンドウへ戻れる。
- 折りたたみ・展開状態は文書の再解析で無条件にリセットしない。
- 長いタイトルを切る場合も、その場で全文確認できる。

### 8.1 左右分離

- 左: 書籍の目次。
- 中央: Markdown本文。
- 右: ページ内見出し。
- 下: 前後ページ名と移動キー。

広い画面で全体と現在地を同時に把握しやすい。左右のUIが本文幅を圧迫するため、幅が足りなければ右の見出しをfloatingへ切り替える。

### 8.2 ツリー統合（既定）

- 左: 書籍の目次。現在ページの直下だけページ内見出しを展開。
- 中央: Markdown本文。
- winbar等: 現在ページ / 現在見出し。
- 下: 前後ページ。

書籍階層と見出し階層はindent、短い記号、ハイライトで区別する。見出しを展開しても、書籍のノード数・読み順は変えない。

大きな章では見出しを折りたためるようにする。本文のカーソル追従でサイドバーを更新しても、サイドバーでユーザーが操作中なら選択カーソルを奪わない。

### 8.3 必要時に表示

- 通常は本文幅を優先する。
- 書籍の目次をtoggle可能なsidebarで開く。
- ページ内見出しをfloatingで開く。
- 前後ページと現在見出しは控えめな1行表示。

狭い端末や集中して読むとき向け。floatingは本文を覆うため、選択後に閉じて元の文書へ戻る。

### 8.4 Neovimでの実装方針

- サイドバーは専用のscratch bufferとsplit windowで実装する。
- floatingも通常のNeovim buffer / windowで実装する。
- 目次の表示行とnode ID / heading IDを別mapで対応付ける。表示テキストからIDを再解析しない。
- 色は名前付きhighlight groupで定義し、既存テーマへdefault linkする。
- `ColorScheme`変更時に追従する。プラグインがテーマ全体を書き換えない。
- 読書表示用の配色を切り替え可能にする。切り替えは読書表示だけに適用し、原文や他のウィンドウに波及させない。
- 幅はセル単位で計算する。全角、結合文字、絵文字、tabを含む見出しで試す。
- マウス操作は任意。キーボードのみで全操作を完結させる。
- statusline / winbarを使う場合はformatter関数を公開し、既存の設定に組み込めるようにする。無条件上書きはしない。
- 前後ページの常時表示を独立した1行ウィンドウで実装する場合、resizeと文書ウィンドウのcloseに追従して破棄する。
- 設定値より狭い画面ではサイドバー幅を制限し、本文の最低幅を優先する。

### 8.5 コマンドとキーマップ

機能は`MdReadable`のサブコマンドとLua APIで提供する。ユーザーが自由にキーや自動実行へ割り当てられるよう、機能本体とキーマップを分離する。`MdReadable vert`で原文と読書表示を左右に並べ、`MdReadable float`で読書表示をfloatingに開く。同じウィンドウでの読書表示も提供する。

開閉、原文へ戻る、同期、目次、見出し、前後ページ、リンク、原文検索、Focus、テーマ、ミニマップ、表の整形と行列操作、画像の取得許可、Refresh、diagnosticsをコマンドから利用可能にする。初期コマンド案は最終確認事項に記載する。

通常文書bufferの標準操作は変更しない。読書bufferでは合意済みの原文コピーのために`y`の意味を変更する。`/`は表示テキストの通常検索を維持する。サイドバー専用bufferでは`j/k`、Enter、`h/l`、`q`による操作を提供し、目次選択後に本文へ戻れるようにする。

## 9. セッションと更新

1. Sessionは対象の文書ウィンドウを保持する。サイドバーbufferを現在の文書として扱わない。
2. 同じ文書を複数ウィンドウで開いた場合、現在見出し・読書位置はウィンドウ側の状態として持つ。
3. プロジェクトのSnapshotは共有できるが、選択tree、選択ノード、折りたたみ、UI配置はsession単位とする。
4. 前後移動前に現在位置とviewを記録し、戻るときに復元する。
5. 明示anchorや見出しを指定した移動では、その指定を読書位置の復元より優先する。
6. unsavedな編集bufferを破棄しない。通常のNeovim編集動作と共存する。
7. 文書外へジャンプする際のjumplistへの記録方針を決め、標準の戻る操作で復帰できることを確認する。
8. 設定保存・文書保存・明示Refreshを最初の更新契機とする。編集中見出しの追従はdebounceする。
9. 非同期解析にはgeneration IDを付け、古い結果が新しいSnapshotを上書きしないようにする。
10. 解析失敗時に直前の正常なSnapshotを保持する場合は、stale状態を表示する。
11. タイマー・autocmd・watcherはsession終了時に破棄し、再起動で多重登録しない。
12. 原文と読書表示を同期している組では、ページ移動も双方向に同期する。元の文書の未保存内容を破棄しない。
13. Neovim終了をまたぐ読書位置・UI状態の保存と復元は実装対象外とする。

## 10. 読書表示と操作

### 10.1 読むbufferと書くbuffer

- 書くbufferを唯一の正本とする。未保存の編集も読むbufferに反映する。
- 読むbufferは `nofile` / `modifiable=false` 相当の派生bufferとし、保存対象にしない。
- 完成時の読書表示には記法の描画、段落の折返し、URL省略、表の整列・省略、画像・図を含む。元と同じテキストを写しただけでは完成としない。
- `scrollbind` / `cursorbind`や同じ行番号だけで同期を成立させようとしない。省略や折り返しによって座標は変わる。
- `SourceMap`を必須とし、表示上の範囲→元ソース範囲、元位置→対応する表示位置を解決する。
- 省略領域は元範囲全体に対応付ける。曖昧な位置ではブロック先頭へ移り、必要なら展開する。
- ユーザーが操作した側から同期し、プログラムによる移動が逆方向の同期を再発火しないよう抑制する。
- ノード解析は元buffer基準とする。読書表示の通常の`/`は表示テキストを検索し、原文全体の検索は専用コマンドで提供する。原文検索では省略箇所も対象に含め、結果への移動時に該当範囲を表示する。
- 読書表示の標準`y`は対応する原文をコピーする。コピー用の対応関係は行番号だけで済ませず、変換した要素の原文範囲も保持する。
- リンクラベルの一部分を選択した場合、その部分の文字列をコピーする。ラベル全体を選択した場合、リンク先とMarkdown記法を含む原文のリンク全体をコピーする（Q21）。
- 例: `[導入手順](installation.md)`の読書表示で「導入」の選択は`導入`、「導入手順」全体の選択は`[導入手順](installation.md)`。原文の空白・エスケープ等を勝手に正規化しない。
- 省略記号を含むセル選択は、隠れた内容を含む元セル全体に対応させる。生成した罫線等を原文としてコピーしない。具体的な選択規則は最終確認事項にも記載する。

### 10.2 Focus

- `limelight.vim`の動作を基準とする（Q12）。従来のMarkdown意味ブロック単位の暫定案は採用しない。
- 参照箇所: `~/ex_prog/ex_lua/apps/limelight.vim/autoload/limelight.vim`の`s:getpos`、`s:limelight`、`s:hl`、`s:on`、`limelight#execute`、およびREADMEのUsage / Options。
- 通常時は空白行で区切られる段落を対象にし、カーソル移動に追従する。Markdownの見出し・表・コードを特別扱いしない。
- 空白行上の範囲判定も参照挙動に合わせる。単一空行・連続空行・文書の先頭末尾・前後段落追加をfixtureで検証し、空白行上の挙動を単純化して実装しない。
- 明示した行範囲やVisual選択範囲に対して起動した場合、その行範囲を固定し、カーソルを移動しても追従しない。単にVisualモードへ入ることと、Visual範囲を指定して起動することを区別する。
- 対象外の文字を減光し、対象範囲は通常表示にする。上位見出しを対象外減光から除外する従来案は採用しない。
- 参照実装の既定値は減光係数0.5、前後に追加する段落数0、ハイライト優先度10。段落の開始・終了パターン、減光色、係数、段落数、優先度を設定できる。係数の範囲は0～1。
- 有効化・無効化・切り替えをコマンドから操作可能にする。limelight.vimを必須依存にせず、段落追従・範囲固定・減光の機能を本プラグイン内に実装する。
- Focusは読書表示だけに適用し、原文や他のウィンドウへ波及させない。参照実装のグローバルautocmdによる適用範囲は再現しない。

### 10.3 省略と表

- URLはリンク文字列やhost等、判断に必要な部分を残す。
- 表は列幅を抑えて長いセルを省略し、行の一覧性を優先する。省略したセル全文は操作で確認できるようにする。
- 表は識別列を残し、隠した列・行数を示す。省略の有無を分かるようにする。
- 必ず展開またはfloatingで元の内容を確認できる。
- 表示上の整列とファイルを書き換えるformatは別操作にする。
- 表のcellにあるescaped pipe、inline code、全角、結合文字を考慮する。
- 読むbufferの標準`y`では表示用の罫線・省略記号ではなく、対応する原文をコピーする。この方針をREADMEに明記する。

### 10.4 フォーマット

プラグインから統一したformat操作を提供する。表の整形機能は本プラグイン内に実装し、vim-table-modeや外部formatterの導入を必須にしない。formatter境界を交換可能にする場合も、内蔵実装を省略しない。

整形は明示操作で実行する。差分がない場合は書き換えず、変更は通常のundoで戻せる単位にまとめる。

行・列の挿入削除も内蔵する。行は現在行の前後、列は現在列の前後へ追加でき、削除と操作数の指定も扱う。読書表示で操作した場合は対応する原文の表へ編集を適用し、再描画・同期する。読み取り操作だけでは発火させず、自動保存しない。vim-table-modeには専用の行挿入実装がないため、行挿入はユーザー要件として追加実装する。ヘッダー・区切り行・最終列等の境界は原文の表構造を壊さないよう検証する。

### 10.5 コード・画像・Mermaid

- コードハイライトは利用可能なsyntax / Tree-sitter連携を使う。parserがなければ平文に戻し、本文は読めるようにする。
- 画像・Mermaidは任意provider。基本ナビゲーションのロードや動作を妨げない。
- 画像・Mermaidの表示機能自体は実装必須であり、任意なのは利用環境でのprovider・外部ツールの導入と有効化である。対応環境では画面内に入った画像・図を本文内へ自動表示する。
- 端末内表示、floatingでの表示、外部ビューアへの委譲を分離する。
- 未対応環境ではalt text、ファイル名、コードを残して開く操作を提供する。
- Mermaidの入力は元コードを保持する。描画失敗時に空白へ置き換えない。
- 外部コマンドは文字列連結のshell実行ではなくargvで起動する。図コードやファイル名をshell構文として解釈させない。
- 外部画像は既定では取得しない。ユーザーの操作または設定で許可した場合に取得・表示する。図・画像キャッシュは入力変更で無効化する。

### 10.6 ミニマップとGit・LSP注釈

neominimap.nvimを参考に、読書表示の縮小表現と現在行の追従、ミニマップから本文への移動を内蔵する。既定は非表示で、コマンドにより開閉する。縮小表現はBraille文字を基本とし、読書表示の省略・折返しによる行数変化を考慮する。

Git差分とLSP診断は元の文書bufferに対する情報を使い、SourceMapで読書表示へ対応付けてから縮小座標へ変換する。LSP診断はNeovim標準の診断情報を利用し、別のLSPクライアントを実装しない。削除差分・複数の診断が同じ縮小行に重なる場合・古い結果・注釈消去を検証する。Git比較基準と注釈の既定値は最終確認事項に記載する。

### 10.7 外部picker連携

md-render.nvimのTelescopeとSnacks連携を参考に、Markdownや画像のpreviewを本プラグインの描画へ差し替えられるAPIを内蔵する。Telescope / Snacksはその連携を利用する場合だけの任意依存とし、未導入でも基本機能をロードできる。

ファイル一覧のMarkdown描画、grep結果の原文行に対応したpreview位置、項目の高速切り替え時の古い描画破棄、picker終了時の画像・window・非同期処理の破棄を検証する。非対応ファイルは元のpreviewへ戻す。選択確定時のactionはpickerの既定を維持する。動画再生はこの連携の追加によって必須範囲へ含めない。

## 11. 品質・依存・導入

- 基本機能はLuaを中心に実装し、formatterや画像関連の重い依存は任意にする。
- AGENTS.mdの4つの参考プラグインは必須依存にせず、対応する機能を本プラグイン内に実装する。コードを再利用する場合は各ライセンスの条件と著作権表示を保持する。
- 初回導入は通常のNeovimプラグインとして可能にし、SSGごとのビルドを必須にしない。
- コア処理はNeovim UIから分離してテストできる構造にする。
- 1,000ページ程度のfixtureを用い、初期解析と再解析の時間を記録する。現時点で根拠のない性能保証は置かない。
- カーソル移動のたびにプロジェクト全体を再解析しない。
- ファイルパス、外部リンク、エラーメッセージをshell commandやEx commandに無加工で連結しない。
- 設定読込、表示、サイドバー移動で文書・SSG設定を変更しない。
- health checkでNeovim版、parser、任意依存、選択adapter、未対応機能を確認できるようにする。
- 既存プラグインとの組み合わせを許容し、特定のpickerやstatuslineプラグインを必須にしない。

## 12. ディレクトリ構成

```text
lua/md-readable/init.lua
lua/md-readable/config.lua
lua/md-readable/health.lua
lua/md-readable/types.lua
lua/md-readable/navigation/{model,index,order,resolver,detect}.lua
lua/md-readable/adapters/{registry,common,mdbook,honkit,gitbook,mkdocs,zensical,docusaurus,astro}.lua
lua/md-readable/parsers/{summary,yaml,toml,frontmatter,literal,sidebar_static}.lua
lua/md-readable/document/{parser,outline,links,blocks,table,extensions}.lua
lua/md-readable/ui/{navigation,theme,links,cell}.lua
lua/md-readable/reader/{render,session,source_map,focus,yank,search}.lua
lua/md-readable/renderers/{text,inline,code,table,extensions}.lua
lua/md-readable/table/{format,edit}.lua
lua/md-readable/providers/{navigation,image,mermaid}.lua
lua/md-readable/image/{capabilities,cache,convert,display,download}.lua
lua/md-readable/minimap/{init,render,git,diagnostic}.lua
lua/md-readable/integrations/{preview,telescope,snacks}.lua
lua/telescope/_extensions/md_readable.lua
plugin/md-readable.lua
doc/md-readable.txt
tests/fixtures/
README.md
```

`ui/navigation.lua`は目次・見出しアウトライン・前後ページ表示を一つのパネル実装で扱う。`minimap/init.lua`がミニマップの公開入口で、`render`・`git`・`diagnostic`はその内部部品である。`types.lua`はLuaLS用の型注釈（`---@meta`）で、実行時には読み込まない。空のモジュールは置かない。

## 13. 並列実装と受け入れ条件

1. 共通契約・fixture・テスト起動を確定する（I00）。
2. 文書解析、SourceMap、ナビゲーションcore、設定parser、SUMMARY parserを並列実装する。
3. 各契約が揃った領域から、基本描画、SSGアダプター、表整形へ進む。
4. Sessionで読書表示とナビゲーションを接続し、各UI・Focus・テーマ・画像・ミニマップを並列に接続する。
5. 画像にMermaid、ミニマップにGit/LSP注釈、描画にpicker連携、表整形に行列編集を接続する。
6. 統合担当が全機能のコマンド・設定・health・README/helpと受け入れ結果をまとめる。

機能担当は専用ファイルと専用テストを所有し、共有の公開入口やREADMEを各自で同時変更しない。依存のない機能は独立worktreeで並列実装する。個別の先行関係と完了条件は[実装Issue一覧](docs/implementation-issues.md)を参照する。

### 必須の検証ケース

| 分類 | ケース |
| --- | --- |
| 共通モデル | ネスト、本文を持つカテゴリ、外部リンク、draft、重複した文書参照、ID重複 |
| 移動 | 先頭・末尾、非掲載ページ、存在しないファイル、同一文書の複数出現、複数tree |
| パス | 相対パス、空白、日本語、anchor、異なるroot、URLとファイルの区別 |
| 見出し | ATX、Setext、コード内の `#`、frontmatter、同名見出し、日本語、レベル飛び |
| 状態 | 別ウィンドウへの移動、未保存buffer、読書位置復元、stale解析結果、window close |
| UI | 80 / 120列程度の端末、長いタイトル、Nerd Fontなし、明暗テーマ、キーボードのみ |
| 副作用 | 読むだけではファイル差分なし、キーマップとstatuslineを無条件上書きしない |
| アダプター | 7対象それぞれに正常系・未対応構文・root変更・順序のfixture |
| 投影 | 行数が変わる省略、全角・byte列、往復同期のループ、検索結果への移動 |
| コピー | リンク部分/全体、reference link、省略セル、装飾だけ、文字/行/矩形選択、指定レジスタ |
| 表編集 | 行列の前後追加とcount付き削除、header/区切り整合、Readからの操作、undo、保存なし |
| 注釈 | 未保存Git差分、削除位置、診断の重大度/解消、原文から縮小表示への対応 |
| picker | Telescope/Snacks、同一fileの別grep結果、未導入、高速切替、終了後の画像破棄 |

パーサーと順序計算、座標変換には意味のある自動テストを置く。UIの色指定をそのまま写すだけのテストは不要。ユーザー操作はheadless Neovimで確認できるものと実端末での手動確認を分ける。

## 14. 実装への引き継ぎ

追跡Issueと各機能IssueをGitHubへ起票済み。各Issueには目的、担当ファイル、入出力、先行Issue、具体的な受け入れ条件と検証方法を記載した。共通契約の変更は統合担当が調整し、複数のエージェントが各自で別の型や座標規約を作らない。

仕様に影響しない実装上の選択は担当エージェントが判断して理由を残す。表示の細部は初期実装を確認して改善するが、必須機能を削除したり、参考プラグインへの必須依存へ置き換えたりしない。

## 15. 参考資料と仕様確認先

SSGの設定仕様は更新される。以下は2026-09-29時点の設計確認に使った公式資料。実装する形式の詳細と利用APIは、導入する版の資料・fixtureで再確認すること。

- [S1: mdBook — SUMMARY.md](https://rust-lang.github.io/mdBook/format/summary.html)
- [S2: HonKit — Configuration](https://honkit.netlify.app/config.html)
- [S3: GitBook — Content configuration](https://gitbook.com/docs/docs-as-code/git-sync/content-configuration)
- [S4: MkDocs — Configuration](https://www.mkdocs.org/user-guide/configuration/)
- [S5: Zensical — Navigation](https://zensical.org/docs/setup/navigation/)
- [S6: Docusaurus — Autogenerated sidebars](https://docusaurus.io/docs/sidebar/autogenerated)
- [S7: Astro — Content collections](https://docs.astro.build/en/guides/content-collections/)
- [S8: Starlight — Sidebar Navigation](https://starlight.astro.build/guides/sidebar/)
- [Neovim — API](https://neovim.io/doc/user/api/)
- [ghostwriter](https://ghostwriter.kde.org/ja/) — Focus Modeの発想の参考
- [vim-limelight](https://github.com/junegunn/limelight.vim) — 周辺の抑制の参考

本書は単独で実装を開始できることを意図しており、過去のHTMLデモやチャット本文の参照を必須にしない。
