return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local actions = require("md-readable.actions")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  local function open(opts)
    cleanup()
    vim.o.columns, vim.o.lines = 160, 40
    api.setup(vim.tbl_deep_extend("force", {
      navigation = { auto_open = false },
      images = { enable = false },
      minimap = { enable = false },
      focus = { enable = false },
      debounce = 0,
    }, opts or {}))
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# One", "", "text", "", "# Two", "", "text" })
    return api.open("current")
  end
  local function book(s)
    local panel = s._navigation and s._navigation.panels.book
    return panel and vim.api.nvim_win_is_valid(panel.win) and panel or nil
  end

  t.test("nav and outline toggle the same automatically placed panel", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local s = open()
    t.eq(nil, book(s))
    actions.toggle_nav({ float = true })
    t.ok(book(s) and not book(s).floating, "legacy float argument does not override width")
    vim.cmd("MdReadable outline sidebar")
    t.eq(nil, book(s), "outline closes the same panel")
    vim.cmd("MdReadable outline")
    t.ok(book(s))
    t.eq(nil, s._navigation.panels.outline)
    vim.cmd("MdReadable nav float")
    t.eq(nil, book(s))
    vim.o.columns = 60
    actions.toggle_nav({ float = false })
    t.ok(book(s).floating, "narrow width wins over legacy sidebar argument")
    local p = book(s)
    for i, entry in ipairs(p.entries) do
      if entry.kind == "heading" and entry.heading.title == "Two" then
        vim.api.nvim_win_set_cursor(p.win, { i, 0 })
      end
    end
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "xt", false)
    t.eq(nil, book(s))
    t.eq(false, s._navigation.open)
    t.eq(s.read_win, vim.api.nvim_get_current_win())
    local row = s.map:to_source(vim.api.nvim_win_get_cursor(s.read_win)[1] - 1, 0)
    t.eq(4, row)
    vim.o.columns = 160
    vim.api.nvim_exec_autocmds("VimResized", {})
    vim.wait(30)
    t.eq(nil, book(s), "selection closes the panel even after resize")
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
  end)

  t.test("floating readers use floating contents even on wide screens", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local s = open()
    sessions.close(s)
    s = api.open("float")
    t.eq(nil, s.snapshot)
    t.eq(nil, book(s))
    local source_win = s.source_win
    vim.cmd("MdReadable outline")
    t.ok(book(s) and book(s).floating)
    t.ok(vim.api.nvim_win_is_valid(source_win))
    t.eq(s.source_buf, vim.api.nvim_win_get_buf(source_win))
    vim.api.nvim_feedkeys(vim.keycode("q"), "xt", false)
    t.eq(nil, book(s))
    t.eq(s.read_win, vim.api.nvim_get_current_win())
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
  end)

  t.test("SSG detection waits for navigation, including saves and link navigation", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local detect = require("md-readable.navigation.detect")
    local original, calls = detect.load, 0
    detect.load = function(...)
      calls = calls + 1
      return original(...)
    end
    local ok, err = xpcall(function()
      local root = t.tempdir()
      t.write(root .. "/book.toml", { "[book]" })
      t.write(root .. "/src/SUMMARY.md", { "- [One](one.md)", "- [Two](two.md)" })
      t.write(root .. "/src/one.md", { "# One" })
      t.write(root .. "/src/two.md", { "# Two" })
      local s = open()
      s:navigate(root .. "/src/one.md")
      s:refresh()
      vim.api.nvim_exec_autocmds("BufWritePost", { buffer = s.source_buf })
      t.eq(0, calls, "open, link, refresh and write do not scan")
      t.ok(require("md-readable.ui.navigation").move(s, "next"))
      t.eq(1, calls, "first page move detects once")
      t.eq(root .. "/src/two.md", s.document.path)
      t.eq(nil, book(s), "page move does not open a panel")
      actions.toggle_nav()
      t.eq(1, calls, "opening uses the loaded snapshot")
      actions.toggle_nav()
      actions.toggle_nav()
      t.eq(1, calls, "reopening does not scan again")
    end, debug.traceback)
    detect.load = original
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
    if not ok then
      error(err)
    end
  end)

  t.test("configured keymaps also work in the navigation, minimap and links panels", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local minimap = require("md-readable.minimap")
    local s = open({
      minimap = { enable = true },
      keymaps = {
        ["gN"] = {
          mode = "n",
          function()
            require("md-readable.actions").toggle_nav({ float = true })
          end,
          desc = "Toggle Nav on Floating Window",
        },
        ["gX"] = "actions.toggle_focus",
      },
    })
    local function press(keys)
      vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
    end
    -- Navigation sidebar: a user key toggles the same panel.
    actions.toggle_nav({ float = false })
    t.eq(book(s).win, vim.api.nvim_get_current_win())
    press("gN")
    t.eq(nil, book(s), "gN in the sidebar closes it")
    press("gN")
    t.ok(book(s))
    -- Panel keys win over reader keys on the same key: q closes the panel.
    press("q")
    t.eq(nil, book(s), "q closes the panel")
    t.ok(not s.closed, "not the reading view")
    -- Minimap: the default go toggles it from inside, a user key reaches the session.
    local state = assert(minimap.get(s))
    vim.api.nvim_set_current_win(state.win)
    press("gX")
    t.eq(true, s.focus_enabled, "gX in the minimap toggles Focus")
    press("go")
    t.eq(nil, minimap.get(s), "go in the minimap closes it")
    -- Links panel.
    vim.api.nvim_set_current_win(s.read_win)
    require("md-readable.ui.links").open(s)
    t.eq(s._links_panel.win, vim.api.nvim_get_current_win())
    t.eq(s, sessions.current(), "the links panel resolves its session")
    press("gX")
    t.ok(not s.focus_enabled, "gX in the links panel")
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
  end)
end
