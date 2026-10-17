# デモ素材の作り方

README に載せている動画とスクショは、すべてリポジトリ直下で次のコマンドを実行して作ります。

| 出力 | コマンド | 内容 |
| --- | --- | --- |
| `assets/readable.gif` | `vhs assets/tapes/readable.tape` | 読書用バッファ、ミニマップ、アウトライン、Focus モード |
| `assets/focus.png` | `vhs assets/tapes/focus.tape` | Focus モード |
| `assets/minimap.png` | `vhs assets/tapes/minimap.tape` | ミニマップ |
| `assets/media.png` | `assets/tapes/media.sh` | 画像と Mermaid (mmdc / termaid) |
| `assets/ssg.gif` | `vhs assets/tapes/ssg.tape` | mdBook の目次からのページ移動 |

- 共通の表示設定は `settings.tape`、Neovim の設定は `assets/demo/init.lua`、題材の文書は `assets/demo/` にあります。
- vhs には `ttyd` と `ffmpeg` が必要です。フォントは Ioskeley Mono JP NF を使い、無ければ他の等幅フォントになります。
- vhs (xterm.js) は Kitty 画像プロトコルを表示できないため、`media.png` だけは `ghostty-shot.sh` で Xvfb 上の Ghostty から撮影します。Ghostty、Xvfb、ImageMagick、mmdc、termaid が必要です。
