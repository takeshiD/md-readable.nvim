# デモ6: リンク移動。同じ読書用バッファのまま別文書や見出しへ移動し、Ctrl-O で戻る
# 打鍵は screenkey.nvim で右下に表示する（assets/demo/init.lua で読み込む）
# 実行: リポジトリ直下で `vhs assets/tapes/jump_link.tape`
Output "assets/jump_link.gif"
Source "assets/tapes/settings.tape"

Hide
Type "nvim -u assets/demo/init.lua assets/demo/jump_link.md" Enter
Sleep 1.5s
Type ":MdReadable" Enter
Sleep 1s
# 打鍵表示 (screenkey.nvim) を開始。ここまでの打鍵は映さない
Type ":Screenkey" Enter
Sleep 1.5s
Show

Sleep 1.5s
# 一覧のリンクから別の文書を開く
Type "/Loading"
Sleep 300ms
Enter
Sleep 800ms
Enter
Sleep 2s

# 文書内の「Next」リンクで次の文書へ
Type "/Ordering"
Sleep 300ms
Enter
Sleep 800ms
Enter
Sleep 2s

# 「Back to the index」で一覧に戻る（元の位置が復元される）
Type "gg"
Sleep 300ms
Type "/Back"
Sleep 300ms
Enter
Sleep 800ms
Enter
Sleep 2s

# 見出し付きのリンクで、別文書の該当見出しへ直接移動
Type "/Handling"
Sleep 300ms
Enter
Sleep 800ms
Enter
Sleep 2s

# Ctrl-O で移動前の位置へ戻る
Ctrl+O
Sleep 2s
