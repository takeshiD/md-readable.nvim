-- Real TUI resize smoke: nvim --headless -n -u NONE -i NONE -l tests/pty_navigation.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./?.lua;" .. package.path
local t = require("tests.helpers")
local root, socket = t.tempdir(), vim.fn.tempname()
t.write(root .. "/book.toml", { "[book]" })
t.write(root .. "/src/SUMMARY.md", { "- [One](one.md)", "- [Two](two.md)" })
t.write(root .. "/src/one.md", { "# One", "", "## Child", "", "text" })
t.write(root .. "/src/two.md", { "# Two" })
local job = vim.fn.jobstart({ vim.v.progpath, "-n", "-u", "NONE", "-i", "NONE", "--listen", socket }, {
  pty = true,
  width = 120,
  height = 24,
  env = { TERM = "xterm-256color" },
  on_stdout = function(id, data)
    -- A minimal terminal response lets Neovim finish background detection.
    if table.concat(data, "\n"):find("\27[5n", 1, true) then
      vim.fn.chansend(id, "\27[0n")
    end
  end,
})
local channel
local function run(code, args)
  return vim.rpcrequest(channel, "nvim_exec_lua", code, args or {})
end
local function wait_for(code)
  if not vim.wait(3000, function()
    return run(code)
  end, 20) then
    error("TUI timeout: " .. code .. "\n" .. vim.inspect(run([[
      return {mode=vim.fn.mode(1), current=vim.api.nvim_get_current_win(),
        columns=vim.o.columns, messages=vim.api.nvim_exec2("messages", {output=true}).output}
    ]])))
  end
end
local ok, err = xpcall(function()
  assert(job > 0, "could not start Neovim PTY")
  assert(
    vim.wait(3000, function()
      local connected, result = pcall(vim.fn.sockconnect, "pipe", socket, { rpc = true })
      if connected then
        channel = result
      end
      return channel ~= nil and channel > 0
    end, 20),
    "could not connect to TUI"
  )
  -- RPC is available during startup; do not modify windows before VimEnter.
  wait_for("return vim.v.vim_did_enter == 1")
  run(
    [[
    local cwd, path = ...
    vim.opt.runtimepath:prepend(cwd)
    vim.cmd("runtime plugin/md-readable.lua")
    require("md-readable").setup({
      minimap = { enable = false }, focus = { enable = false },
      watch = { enable = false }, images = { enable = false },
    })
    vim.cmd.edit(vim.fn.fnameescape(path))
    _G.s52 = require("md-readable").open("current")
    assert(not s52.snapshot and not s52._navigation.open)
    vim.cmd("MdReadable nav")
  ]],
    { vim.fn.getcwd(), root .. "/src/one.md" }
  )
  wait_for("return s52._navigation.panels.book and not s52._navigation.panels.book.floating")
  run([[
    local p = s52._navigation.panels.book
    for i, e in ipairs(p.entries) do
      if e.kind == "heading" and e.heading.title == "Child" then
        _G.selected52 = e.id
        vim.api.nvim_win_set_cursor(p.win, {i, 0})
        return
      end
    end
    error("heading missing from combined tree")
  ]])
  for _, width in ipairs({ 60, 120, 60 }) do
    assert(vim.fn.jobresize(job, width, 24) == 1)
    wait_for(string.format(
      [[
      local p = s52._navigation.panels.book
      local row = p and vim.api.nvim_win_get_cursor(p.win)[1]
      return vim.o.columns == %d and p and p.floating == %s
        and vim.api.nvim_get_current_win() == p.win
        and p.entries[row].id == selected52
    ]],
      width,
      tostring(width < 77)
    ))
  end
  vim.rpcrequest(channel, "nvim_input", "<CR>")
  wait_for("return not s52._navigation.open and vim.api.nvim_get_current_win() == s52.read_win")
  run([[
    local row = s52.map:to_source(vim.api.nvim_win_get_cursor(s52.read_win)[1]-1, 0)
    assert(row == 2)
  ]])
  assert(vim.fn.jobresize(job, 120, 24) == 1)
  wait_for("return vim.o.columns == 120")
  run('assert(not s52._navigation.panels.book); vim.cmd("MdReadable outline")')
  wait_for("return s52._navigation.panels.book and not s52._navigation.panels.book.floating")
  assert(vim.fn.jobresize(job, 60, 24) == 1)
  wait_for("return s52._navigation.panels.book and s52._navigation.panels.book.floating")
  vim.rpcrequest(channel, "nvim_input", "<Esc>")
  wait_for("return not s52._navigation.open and vim.api.nvim_get_current_win() == s52.read_win")
  run([[
    vim.cmd("MdReadable nav")
    local p = s52._navigation.panels.book
    for i, e in ipairs(p.entries) do
      if e.kind == "node" and e.node.title == "Two" then
        vim.api.nvim_win_set_cursor(p.win, {i, 0})
        return
      end
    end
    error("next page missing")
  ]])
  vim.rpcrequest(channel, "nvim_input", "<CR>")
  wait_for("return not s52._navigation.open and s52.document.path:match('/two.md$') ~= nil")
  run('vim.cmd("MdReadable close"); assert(vim.bo.modified == false)')
end, debug.traceback)
if channel and channel > 0 then
  pcall(vim.rpcnotify, channel, "nvim_command", "qa!")
end
vim.fn.jobstop(job)
vim.fn.delete(socket)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
end
print("PTY navigation: wide/narrow round trip, headings/pages, Escape, close: PASS")
vim.cmd("qa!")
