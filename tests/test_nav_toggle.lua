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

  t.test("toggle_nav opens a sidebar or a floating window on request", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local s = open()
    actions.toggle_nav({ float = true })
    t.ok(book(s) and book(s).floating, "floating window")
    t.eq("editor", vim.api.nvim_win_get_config(book(s).win).relative)
    vim.api.nvim_set_current_win(s.read_win)
    actions.toggle_nav({ float = false })
    t.ok(book(s) and not book(s).floating, "the other style reopens as a sidebar")
    t.eq("", vim.api.nvim_win_get_config(book(s).win).relative)
    vim.api.nvim_set_current_win(s.read_win)
    actions.toggle_nav({ float = false })
    t.eq(nil, book(s), "the same style closes it")
    -- The plain action keeps choosing by width and layout.
    actions.toggle_nav()
    t.ok(book(s) and not book(s).floating, "wide integrated layout: sidebar")
    vim.api.nvim_set_current_win(s.read_win)
    actions.toggle_nav()
    t.eq(nil, book(s))
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
  end)

  t.test("float and sidebar toggles are available as keymaps, commands and named actions", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local s = open({
      keymaps = {
        ["gN"] = {
          mode = "n",
          function()
            require("md-readable.actions").toggle_nav({ float = true })
          end,
          desc = "Toggle Nav on Floating Window",
        },
        ["gS"] = "actions.toggle_nav_sidebar",
      },
    })
    vim.api.nvim_feedkeys(vim.keycode("gN"), "xt", false)
    t.ok(book(s) and book(s).floating, "function keymap")
    vim.api.nvim_set_current_win(s.read_win)
    vim.api.nvim_feedkeys(vim.keycode("gS"), "xt", false)
    t.ok(book(s) and not book(s).floating, "named action")
    vim.api.nvim_set_current_win(s.read_win)
    vim.cmd("MdReadable nav float")
    t.ok(book(s) and book(s).floating, ":MdReadable nav float")
    t.eq("Toggle book navigation in a floating window", actions.get("toggle_nav_float").desc)
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
  end)

  t.test(":MdReadable outline opens page headings as a float or a right sidebar", function()
    local columns, lines = vim.o.columns, vim.o.lines
    local s = open()
    local function outline()
      local panel = s._navigation and s._navigation.panels.outline
      return panel and vim.api.nvim_win_is_valid(panel.win) and panel or nil
    end
    vim.cmd("MdReadable outline")
    t.ok(outline() and outline().floating, "floating by default")
    vim.api.nvim_set_current_win(s.read_win)
    vim.cmd("MdReadable outline sidebar")
    local panel = assert(outline())
    t.ok(not panel.floating, "the other style reopens as a sidebar")
    t.eq("", vim.api.nvim_win_get_config(panel.win).relative)
    t.eq(panel.win, vim.api.nvim_get_current_win())
    t.ok(vim.api.nvim_win_get_position(panel.win)[2] > vim.api.nvim_win_get_position(s.read_win)[2], "right side")
    t.eq(nil, book(s), "the book tree stays closed")
    vim.api.nvim_set_current_win(s.read_win)
    vim.cmd("MdReadable outline")
    t.eq(panel.win, assert(outline()).win, "no style given: the open panel is focused")
    t.eq(panel.win, vim.api.nvim_get_current_win())
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
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
    -- Navigation sidebar: a user key reopens it as a float.
    actions.toggle_nav({ float = false })
    t.eq(book(s).win, vim.api.nvim_get_current_win())
    press("gN")
    t.ok(book(s) and book(s).floating, "gN in the sidebar")
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
