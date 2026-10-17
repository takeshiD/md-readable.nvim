#!/usr/bin/env bash
# vhs (xterm.js) は Kitty 画像プロトコルを表示できないため、画像を含むスクショは
# 仮想ディスプレイ (Xvfb) 上の Ghostty で撮影する。
#
# 使い方 (リポジトリ直下で実行):
#   assets/tapes/ghostty-shot.sh <出力.png> <Markdown> [環境変数=値 ...]
# 例:
#   assets/tapes/ghostty-shot.sh assets/media-mmdc.png assets/demo/media.md
#   assets/tapes/ghostty-shot.sh assets/media-termaid.png assets/demo/media.md MD_READABLE_DEMO_MERMAID=termaid
#
# 必要なもの: ghostty, Xvfb (xvfb-run), ImageMagick (import), nvim, mmdc / termaid
set -euo pipefail

out=$1
doc=$2
shift 2

cols=${COLS:-100}
rows=${ROWS:-44}
wait=${WAIT:-12}

if [[ -z ${_GHOSTTY_SHOT_INNER:-} ]]; then
  # Wayland 上で起動すると実画面に窓が出るので、X11 の仮想ディスプレイに限定する
  exec env -u WAYLAND_DISPLAY GDK_BACKEND=x11 _GHOSTTY_SHOT_INNER=1 \
    xvfb-run -a -s "-screen 0 1920x1200x24" "$0" "$out" "$doc" "$@"
fi

env "$@" ghostty \
  --config-default-files=false \
  --font-family="Ioskeley Mono JP NF" \
  --font-size=12 \
  --theme="TokyoNight" \
  --window-decoration=false \
  --window-width="$cols" \
  --window-height="$rows" \
  --window-padding-x=14 \
  --window-padding-y=12 \
  --window-padding-color=extend \
  -e nvim -u assets/demo/init.lua "$doc" -c "MdReadable" >/dev/null 2>&1 &
pid=$!
sleep "$wait"

# Ghostty の窓だけを切り出す
win=$(xwininfo -root -tree | awk '/[Gg]hostty/ && /[0-9]+x[0-9]+\+/ {print $1; exit}')
if [[ -n $win ]]; then
  import -window "$win" "$out"
else
  import -window root -trim "$out"
fi
kill "$pid" 2>/dev/null || true
