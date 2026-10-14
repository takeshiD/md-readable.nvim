# デモ2: Focus モードのスクショ（カーソルのある段落以外を暗くする）
# 実行: リポジトリ直下で `vhs assets/tapes/focus.tape`
Source "assets/tapes/settings.tape"

Hide
Type "nvim -u assets/demo/init.lua assets/demo/guide.md" Enter
Sleep 1.5s
Type ":MdReadable" Enter
Sleep 1s
Type "/The busy marker" Enter
Type "zz"
Type ":MdReadable focus on" Enter
Sleep 1s
Type ":nohlsearch | echo" Enter
Sleep 300ms
Show
Sleep 500ms
Screenshot "assets/focus.png"
Sleep 300ms
