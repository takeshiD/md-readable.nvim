# デモ2: Focus モードのスクショ（カーソルのある段落以外を暗くする）
# 実行: リポジトリ直下で `vhs assets/tapes/focus.tape`
Output "assets/focus.gif"
Source "assets/tapes/settings.tape"

Hide
Type "nvim -u assets/demo/init.lua assets/demo/guide.md" Enter
Sleep 1.5s
Type ":MdReadable" Enter
Sleep 1s
Type ":MdReadable focus off" Enter
Sleep 1s
Show

Sleep 500ms
Type "15gg" Enter
Sleep 700ms
Type ":MdReadable focus on" Enter
Sleep 700ms
Type "jjjj" Enter
Type "zz" Enter
Sleep 700ms
Type "jjjjjjjjjjjjjjj" Enter
Type "zz" Enter
Sleep 1500ms
