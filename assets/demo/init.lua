-- デモ録画用の最小構成
-- 使い方: nvim -u assets/demo/init.lua <file.md>
-- 環境変数 MD_READABLE_DEMO_MERMAID に "termaid" を渡すと Mermaid を文字で描画する
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
local root = vim.fs.dirname(vim.fs.dirname(here))

vim.opt.runtimepath:prepend(root)
vim.opt.termguicolors = true
vim.opt.laststatus = 3
vim.opt.cmdheight = 1
vim.opt.showmode = false
vim.opt.shortmess:append("IF")
vim.opt.swapfile = false
vim.opt.hlsearch = false
vim.opt.number = false
vim.opt.signcolumn = "no"
vim.cmd.colorscheme("default")

vim.g.mapleader = " "

require("md-readable").setup({
  width = 80,
  focus = { enable = false, coefficient = 0.65 },
  minimap = { enable = false, width = 16 },
  navigation = { enable = false },
  git = { enable = false },
  watch = { enable = false },
  code = { theme = "tokyonight", label = "right" },
  mermaid = {
    renderer = vim.env.MD_READABLE_DEMO_MERMAID or "mmdc",
    mmdc_opts = { no_sandbox = true, theme = "dark" },
    termaid_opts = { padding_y = 0, gap = 2 },
    max_rows = 16,
  },
  images = { height = 10 },
})
