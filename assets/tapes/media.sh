#!/usr/bin/env bash
# デモ4: 画像 / Mermaid (mmdc) / Mermaid (termaid) の表示例を 1 枚にまとめる
# 実行: リポジトリ直下で `assets/tapes/media.sh` → assets/media.png
set -euo pipefail

here=$(dirname "$0")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$here/ghostty-shot.sh" "$tmp/mmdc.png" assets/demo/media.md
"$here/ghostty-shot.sh" "$tmp/termaid.png" assets/demo/media.md MD_READABLE_DEMO_MERMAID=termaid

# 各スクショに窓枠（タイトルバーと角丸）を付ける
frame() {
  local src=$1 title=$2 dst=$3
  local w h
  w=$(magick identify -format %w "$src")
  h=$(magick identify -format %h "$src")
  magick -size "${w}x40" xc:"#16161e" \
    -fill "#ff5f57" -draw "circle 22,20 28,20" \
    -fill "#febc2e" -draw "circle 44,20 50,20" \
    -fill "#28c840" -draw "circle 66,20 72,20" \
    -font DejaVu-Sans -pointsize 16 -fill "#a9b1d6" -gravity center -annotate +0+0 "$title" \
    "$src" -gravity north -append +repage "$tmp/body.png"
  magick -size "${w}x$((h + 40))" xc:none -fill white \
    -draw "roundrectangle 0,0 $((w - 1)),$((h + 39)) 12,12" "$tmp/mask.png"
  magick "$tmp/body.png" "$tmp/mask.png" -alpha off -compose CopyOpacity -composite +repage "$dst"
}

frame "$tmp/mmdc.png" "mermaid.renderer = \"mmdc\"  (Kitty graphics)" "$tmp/a.png"
frame "$tmp/termaid.png" "mermaid.renderer = \"termaid\"  (Unicode text)" "$tmp/b.png"

magick "$tmp/a.png" \( -size 28x1 xc:none \) "$tmp/b.png" -background none +append +repage \
  -bordercolor none -border 28 -background "#414868" -flatten assets/media.png
echo "wrote assets/media.png"
