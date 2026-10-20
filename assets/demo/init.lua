-- Minimap setup for demo
-- Usage: nvim -u assets/demo/init.lua <file.md>
-- When environment variable `MD_READABLE_DEMO_MERMAID` set "termaid", mermaid codeblock is drawn ascii diagram via termaid.
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
  focus = { enable = true, coefficient = 0.65 },
  minimap = { enable = false, width = 16 },
  navigation = { enable = false },
  git = { enable = true },
  watch = { enable = true },
  code = { theme = "ayu-dark", label = "right" },
  mermaid = {
    renderer = vim.env.MD_READABLE_DEMO_MERMAID or "mmdc",
    mmdc_opts = { no_sandbox = true, theme = "dark" },
    termaid_opts = { padding_y = 0, gap = 2 },
    max_rows = 16,
  },
  images = { height = 14 },
})

-- Key display for demos. Loaded from `MD_READABLE_DEMO_SCREENKEY` (a screenkey.nvim checkout),
-- or lazy.nvim's install path; a tape turns it on with `:Screenkey`.
local screenkey = vim.env.MD_READABLE_DEMO_SCREENKEY or (vim.fn.stdpath("data") .. "/lazy/screenkey.nvim")
if vim.fn.isdirectory(screenkey) == 1 then
  vim.opt.runtimepath:append(screenkey)
  require("screenkey").setup({
    win_opts = {
      row = vim.o.lines - vim.o.cmdheight - 2,
      col = vim.o.columns - 2,
      width = 28,
      height = 1,
      border = "rounded",
      title = " Keys ",
    },
    clear_after = 2,
  })
end
