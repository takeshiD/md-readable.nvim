# デモ3: ミニマップのスクショ（見出し・コードを色分けし、現在行を強調）
# 実行: リポジトリ直下で `vhs assets/tapes/minimap.tape`
Output "assets/minimap.gif"
Source "assets/tapes/settings.tape"

Hide
Type "nvim -u assets/demo/init.lua assets/demo/guide.md" Enter
Sleep 1.5s
Type ":MdReadable" Enter
Sleep 1s
Type ":MdReadable minimap on" Enter
Sleep 800ms
Type "/Running Tasks" Enter
Type "zt"
Sleep 500ms
Type ":MdReadable minimap focus" Enter
Sleep 800ms
Type ":nohlsearch | echo" Enter
Sleep 300ms
Show

Sleep 1000ms
Type "jj"
Sleep 500ms
Type "jjjj"
Sleep 700ms
