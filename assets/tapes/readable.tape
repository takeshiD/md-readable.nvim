# デモ1: 読書用バッファを開き、ミニマップ・アウトライン・Focus モードを順に見せる
# 実行: リポジトリ直下で `vhs assets/tapes/readable.tape`
Output "assets/readable.gif"
Source "assets/tapes/settings.tape"

Hide
Type "nvim -u assets/demo/init.lua assets/demo/guide.md" Enter
Sleep 1.5s
Show

# 元の Markdown を見せてから読書用バッファへ
Sleep 1.5s
Type ":MdReadable"
Sleep 400ms
Enter
Sleep 2s

# ミニマップ
Type ":MdReadable minimap on"
Sleep 400ms
Enter
Sleep 1.5s
Ctrl+D
Sleep 900ms
Ctrl+D
Sleep 900ms
Ctrl+U
Sleep 600ms
Ctrl+U
Sleep 1s

# アウトライン（ページ内の見出し）から見出しへ移動
Type ":MdReadable outline"
Sleep 400ms
Enter
Sleep 1.2s
Down@350ms 6
Sleep 600ms
Enter
Sleep 500ms
Type "zt"
Sleep 1.5s

# サイドバーに見出しを常時表示。移動に合わせて本文が追従する
Type ":MdReadable nav sidebar"
Sleep 400ms
Enter
Sleep 1.2s
Type "/Running"
Sleep 300ms
Enter
Sleep 1.2s
Down@700ms 2
Sleep 600ms
Up@700ms 1
Sleep 600ms
Enter
Sleep 300ms
Type "zt"
Sleep 1.2s

# Focus モード: カーソル位置の段落だけを明るく表示
Type ":MdReadable focus on"
Sleep 400ms
Enter
Sleep 1.2s
Type@700ms "}}}}}}"
Sleep 1s
Type@700ms "{{{"
Sleep 2s
