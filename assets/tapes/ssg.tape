# デモ5: SSG (mdBook) サポート。目次ナビゲーションからページを切り替える
# 実行: リポジトリ直下で `vhs assets/tapes/ssg.tape`
Output "assets/ssg.gif"
Source "assets/tapes/settings.tape"

Type "tree assets/demo/book" Enter
Sleep 1s

Hide
Type "nvim -u assets/demo/init.lua assets/demo/book/src/introduction.md" Enter
Sleep 1.5s
Type ":MdReadable" Enter
Sleep 1s
Type ":Screenkey" Enter
Sleep 1s
Show

Sleep 1s
Type ":MdReadable nav sidebar"
Sleep 400ms
Enter
Sleep 2s

# 目次からページを開く
Type "/Getting"
Sleep 300ms
Enter
Sleep 800ms
Enter
Sleep 1s

Ctrl+W
Type "h"
Sleep 500ms
Type "jj"
Sleep 500ms
Enter
Sleep 500ms
Enter
Sleep 1s

Ctrl+W
Type "h"
Sleep 500ms
Type "jjj"
Sleep 500ms
Enter
Sleep 2s
