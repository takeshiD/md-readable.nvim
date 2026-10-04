return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local keymaps = require("md-readable.keymaps")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  local function open(opts)
    cleanup()
    api.setup(vim.tbl_extend("force", { navigation = { auto_open = false }, images = { enabled = false } }, opts or {}))
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, t.tempdir() .. "/keys.md")
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "", "text", "", "## Two", "", "more", "", "## Three" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    return api.open("vert")
  end
  local function mapped(buf, lhs, mode)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode or "n")) do
      if map.lhs == lhs then
        return map
      end
    end
  end
  local function source_row(s)
    return vim.api.nvim_win_get_cursor(s.source_win)[1]
  end

  t.test("default reader keymaps are installed only in the reading buffer", function()
    local s = open()
    for lhs in pairs(keymaps.defaults) do
      t.ok(mapped(s.read_buf, lhs), "missing default " .. lhs)
    end
    t.ok(mapped(s.read_buf, "gz", "x"), "gz should also map Visual mode")
    t.eq(nil, mapped(s.source_buf, "]]"))
    vim.api.nvim_set_current_win(s.read_win)
    vim.cmd("normal ]]")
    t.eq(5, source_row(s))
    vim.cmd("normal ]]")
    t.eq(9, source_row(s))
    vim.cmd("normal [[")
    t.eq(5, source_row(s))
    vim.cmd("normal q")
    t.ok(s.closed, "q closes the reading view")
    cleanup()
  end)

  t.test("user keymaps override, add and disable defaults per key", function()
    local called = 0
    local s = open({
      keymaps = {
        ["]]"] = { mode = "n", "actions.heading-prev", desc = "Back" },
        ["q"] = false,
        ["<leader>x"] = function()
          called = called + 1
        end,
        ["gh"] = { "actions.show_help", desc = "Help" },
      },
    })
    t.eq("Back", mapped(s.read_buf, "]]").desc)
    t.eq(nil, mapped(s.read_buf, "q"))
    t.ok(mapped(s.read_buf, "gO"), "untouched defaults are kept")
    t.eq("Help", mapped(s.read_buf, "gh").desc)
    vim.api.nvim_set_current_win(s.read_win)
    vim.api.nvim_win_set_cursor(s.read_win, { vim.api.nvim_buf_line_count(s.read_buf), 0 })
    vim.cmd("normal ]]")
    t.ok(source_row(s) < 9, "]] was remapped to heading-prev")
    vim.cmd("normal " .. vim.keycode("<leader>x"))
    t.eq(1, called)
    cleanup()
  end)

  t.test("defaults can be turned off and invalid actions fail at setup", function()
    local s = open({ use_default_keymaps = false, keymaps = { ["go"] = "actions.toggle_minimap" } })
    t.eq(nil, mapped(s.read_buf, "]]"))
    t.ok(mapped(s.read_buf, "go"), "explicit keys are kept without defaults")
    s = open({ keymaps = false })
    t.eq(nil, mapped(s.read_buf, "q"))
    local ok, err = pcall(api.setup, { keymaps = { ["x"] = "actions.nope" } })
    t.ok(not ok and tostring(err):find("unknown action", 1, true), tostring(err))
    cleanup()
    api.setup({})
  end)

  t.test("show_help lists the configured keymaps in a float", function()
    local s = open({ keymaps = { ["gh"] = { "actions.toggle_minimap", desc = "Minimap please" } } })
    vim.api.nvim_set_current_win(s.read_win)
    local win, buf = keymaps.help()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    t.ok(text:find("Minimap please", 1, true), text)
    t.ok(text:find("g?", 1, true) and text:find("Copy Markdown source", 1, true), text)
    vim.api.nvim_win_close(win, true)
    cleanup()
  end)
end
