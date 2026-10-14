return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local actions = require("md-readable.actions")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipeout!")
  end
  -- mdBook: book.toml at the root, contents in src/, a README outside them.
  local function book()
    local root = t.tempdir()
    t.write(root .. "/book.toml", { "[book]", 'title = "Book"' })
    t.write(root .. "/README.md", { "# Repository", "", "## Setup", "", "text" })
    t.write(root .. "/src/SUMMARY.md", { "# Summary", "", "- [Intro](intro.md)", "  - [Part](part.md)" })
    t.write(root .. "/src/intro.md", { "# Intro", "", "## Section", "", "### Detail", "", "text", "", "## Other" })
    t.write(root .. "/src/part.md", { "# Part" })
    t.write(root .. "/src/extra.md", { "# Extra", "", "## Not listed" })
    return root
  end
  local function open(path, opts)
    cleanup()
    vim.o.columns, vim.o.lines = 160, 40
    api.setup(vim.tbl_deep_extend("force", {
      images = { enable = false },
      minimap = { enable = false },
      focus = { enable = false },
      git = { enable = false },
      watch = { enable = false },
      debounce = 0,
    }, opts or {}))
    vim.cmd("edit " .. path)
    return api.open("current")
  end
  local function panel(s)
    local p = s._navigation and s._navigation.panels.book
    return p and vim.api.nvim_win_is_valid(p.win) and p or nil
  end
  local function lines(p)
    return vim.api.nvim_buf_get_lines(p.buf, 0, -1, false)
  end
  local function press(keys)
    vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
  end
  local function goto_line(p, text)
    for index, line in ipairs(lines(p)) do
      if line:find(text, 1, true) then
        vim.api.nvim_win_set_cursor(p.win, { index, 0 })
        return index
      end
    end
    error("no line with " .. text .. " in " .. vim.inspect(lines(p)))
  end

  t.test("a file outside the book content gets headings, not the book tree", function()
    local columns, rows = vim.o.columns, vim.o.lines
    local root = book()
    local s = open(root .. "/README.md")
    t.eq(nil, s.snapshot, "no book for the repository README")
    t.eq("outside-content", s.nav_result.diagnostics[1].code)
    t.eq(nil, panel(s), "not opened automatically")
    actions.toggle_nav()
    t.ok(vim.tbl_contains(lines(panel(s)), "- # Repository"), vim.inspect(lines(panel(s))))
    s = open(root .. "/src/intro.md")
    t.ok(s.snapshot, "a page of the book")
    t.ok(panel(s), "opened automatically")
    local model = require("md-readable.navigation.model")
    t.eq("src", model.content_dir(s.snapshot.trees[1]))
    t.ok(model.contains(s.snapshot, root .. "/src/deep/page.md"))
    t.ok(not model.contains(s.snapshot, root .. "/notes.md"))
    cleanup()
    vim.o.columns, vim.o.lines = columns, rows
  end)

  t.test("a page of the book that is not in the contents shows its headings on top", function()
    local columns, rows = vim.o.columns, vim.o.lines
    local root = book()
    local s = open(root .. "/src/extra.md")
    t.ok(s.snapshot, "inside the book content")
    local text = lines(assert(panel(s)))
    t.ok(vim.tbl_contains(text, "Not in the contents"), vim.inspect(text))
    t.ok(vim.tbl_contains(text, "  - ## Not listed") or vim.tbl_contains(text, "    ## Not listed"), vim.inspect(text))
    t.ok(table.concat(text, "\n"):find("Intro", 1, true), "the book tree follows")
    cleanup()
    vim.o.columns, vim.o.lines = columns, rows
  end)

  t.test("fold keys: toggle, recursive and all, with the configured icons", function()
    local columns, rows = vim.o.columns, vim.o.lines
    local root = book()
    local s =
      open(root .. "/src/intro.md", { navigation = { fold = { icons = { collapsed = "▸ ", expanded = "▾ " } } } })
    local p = assert(panel(s))
    vim.api.nvim_set_current_win(p.win)
    goto_line(p, "## Section")
    t.ok(lines(p)[vim.api.nvim_win_get_cursor(p.win)[1]]:find("▾ ## Section", 1, true), "expanded icon")
    press("za")
    t.ok(table.concat(lines(p), "\n"):find("▸ ## Section", 1, true), "za collapses")
    t.ok(not table.concat(lines(p), "\n"):find("Detail", 1, true), "child hidden")
    press("za")
    t.ok(table.concat(lines(p), "\n"):find("Detail", 1, true), "za expands")
    goto_line(p, "Intro")
    press("zC")
    t.ok(not table.concat(lines(p), "\n"):find("Section", 1, true), "zC folds the page and its headings")
    press("zO")
    t.ok(table.concat(lines(p), "\n"):find("Detail", 1, true), "zO opens everything below")
    press("zM")
    local all = table.concat(lines(p), "\n")
    t.ok(not all:find("Part", 1, true) and not all:find("Section", 1, true), "zM folds all: " .. all)
    press("zR")
    all = table.concat(lines(p), "\n")
    t.ok(all:find("Part", 1, true) and all:find("Detail", 1, true), "zR opens all")
    cleanup()
    vim.o.columns, vim.o.lines = columns, rows
  end)

  t.test("fold keys can be replaced or turned off per action", function()
    local columns, rows = vim.o.columns, vim.o.lines
    local root = book()
    local s = open(root .. "/src/intro.md", {
      navigation = { fold = { keys = { collapse = "<BS>", expand = false, toggle = { "<Space>" } } } },
    })
    local p = assert(panel(s))
    t.eq({ "<BS>" }, { s.config.navigation.fold.keys.collapse }, "a key replaces the default list")
    ---@param lhs string
    ---@return boolean
    local function mapped(lhs)
      return vim.api.nvim_buf_call(p.buf, function()
        return not vim.tbl_isempty(vim.fn.maparg(lhs, "n", false, true))
      end)
    end
    t.ok(mapped("<BS>") and mapped("<Space>"), "configured keys")
    t.ok(not mapped("h") and not mapped("<Left>") and not mapped("l"), "replaced and disabled keys are gone")
    t.ok(lines(p)[2]:find("Enter open  q back", 1, true), "no fold hint without an expand key")
    local ok, err = pcall(api.setup, { navigation = { fold = { keys = { toggle = 3 } } } })
    t.ok(not ok and err:find("navigation.fold.keys.toggle must be keys or false", 1, true), tostring(err))
    cleanup()
    vim.o.columns, vim.o.lines = columns, rows
  end)

  t.test("navigation.style decides how toggle_nav opens the book tree", function()
    local columns, rows = vim.o.columns, vim.o.lines
    local root = book()
    local s = open(root .. "/src/intro.md", { navigation = { style = "float" } })
    t.eq(nil, panel(s), "a float never opens by itself")
    actions.toggle_nav()
    t.ok(panel(s) and panel(s).floating, "style float")
    s = open(root .. "/src/intro.md", { layout = "ondemand", navigation = { style = "sidebar" } })
    actions.toggle_nav()
    t.ok(panel(s) and not panel(s).floating, "style sidebar, even with an on-demand layout")
    vim.api.nvim_set_current_win(s.read_win)
    actions.toggle_nav({ float = true })
    t.ok(panel(s) and panel(s).floating, "an explicit choice still wins")
    local ok, err = pcall(api.setup, { navigation = { style = "popup" } })
    t.ok(not ok and err:find('navigation.style must be "auto", "sidebar" or "float"', 1, true), tostring(err))
    cleanup()
    vim.o.columns, vim.o.lines = columns, rows
  end)

  t.test("navigation.enable decides whether the book tree opens with the reading view", function()
    local columns, rows = vim.o.columns, vim.o.lines
    local root = book()
    local s = open(root .. "/src/intro.md", { navigation = { enable = false } })
    t.eq(nil, panel(s), "enable = false: not opened")
    actions.toggle_nav()
    t.ok(panel(s), "gn still opens it")
    s = open(root .. "/src/intro.md", { navigation = { auto_open = false } })
    t.eq(nil, panel(s), "auto_open is the former name")
    t.eq(false, s.config.navigation.enable)
    t.eq(nil, s.config.navigation.auto_open)
    s = open(root .. "/src/intro.md", { navigation = { enable = true, auto_open = false } })
    t.ok(panel(s), "enable wins")
    cleanup()
    vim.o.columns, vim.o.lines = columns, rows
  end)
end
