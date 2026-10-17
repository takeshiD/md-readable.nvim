# デモ5: SSG (mdBook) サポート。目次ナビゲーションからページを切り替える
# 実行: リポジトリ直下で `vhs assets/tapes/ssg.tape`
Output "assets/ssg.gif"
Source "assets/tapes/settings.tape"

Hide
Type "nvim -u assets/demo/init.lua assets/demo/book/src/introduction.md" Enter
Sleep 1.5s
Type ":MdReadable" Enter
Sleep 1s
Show

Sleep 1s
# book.toml と SUMMARY.md から目次を組み立てて表示
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
Sleep 2s

# 前後のページへ移動
Type ":MdReadable next"
Sleep 400ms
Enter
Sleep 1.8s
Type ":MdReadable next"
Sleep 400ms
Enter
Sleep 1.8s

# 目次に戻って別の章へ
Ctrl+W
Type "h"
Sleep 800ms
Type "/Configuration"
Sleep 300ms
Enter
Sleep 800ms
Enter
Sleep 2s

# 目次の折りたたみ
Ctrl+W
Type "h"
Sleep 600ms
Type "/User Guide"
Sleep 300ms
Enter
Sleep 800ms
Type "h"
Sleep 1.2s
Type "l"
Sleep 2s
