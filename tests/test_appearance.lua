return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local theme = require("md-readable.ui.theme")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local source_map = require("md-readable.reader.source_map")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  local function open(lines, mode, config)
    cleanup()
    api.setup(vim.tbl_deep_extend("force", {
      navigation = { auto_open = false },
      images = { enabled = false },
      minimap = { enable = false },
      debounce = 0,
    }, config or {}))
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return api.open(mode or "current")
  end

  t.test("H1 and H2 get display-only rules that map back to the heading", function()
    local source = { "# Intro", "", "Setext", "------", "", "### Third", "body" }
    local value = render(parse(source), { width = 20 })
    t.eq({ "Intro", string.rep("═", 20), "", "Setext", string.rep("─", 20), "", "Third", "body" }, value.lines)
    local map = source_map.new(source, value)
    for _, segment in ipairs(value.segments) do
      t.ok(segment.row ~= 1 and segment.row ~= 4, "rule rows have no source segments")
    end
    t.eq(nil, map:copy(1, 0, 1, #value.lines[2], "char"))
    t.eq(0, (map:to_source(1, 3)))
    t.eq(3, (map:to_source(4, 0)), "setext rule maps to its underline row")
    local groups = {}
    for _, h in ipairs(value.highlights) do
      groups[h.row] = h.group
    end
    t.eq("MdReadableHeading1", groups[0])
    t.eq("MdReadableHeading1", groups[1])
    t.eq("MdReadableHeading2", groups[4])
    t.eq("MdReadableHeading3", groups[6])
    t.eq({ "Intro" }, render(parse({ "# Intro" }), { heading_rules = false }).lines)
  end)

  t.test("heading levels stay distinct in default and preset themes", function()
    vim.cmd("hi clear")
    theme.setup()
    local function hl(ns, level)
      return vim.api.nvim_get_hl(ns, { name = "MdReadableHeading" .. level, link = false })
    end
    for _, pair in ipairs({ { 1, 2 }, { 1, 3 }, { 2, 3 } }) do
      t.ok(not vim.deep_equal(hl(0, pair[1]), hl(0, pair[2])), "default H" .. pair[1] .. "/H" .. pair[2])
    end
    t.ok(hl(0, 1).bold)
    t.ok(vim.api.nvim_get_hl(0, { name = "MdReadableLink", link = false }).fg, "links have a color, not only underline")
    local s = open({ "# A", "## B", "### C" })
    for _, name in ipairs({ "dark", "light" }) do
      local ns = assert(theme.apply(s.read_win, name))
      for _, pair in ipairs({ { 1, 2 }, { 1, 3 }, { 2, 3 } }) do
        t.ok(not vim.deep_equal(hl(ns, pair[1]), hl(ns, pair[2])), name .. " H" .. pair[1] .. "/H" .. pair[2])
      end
    end
    cleanup()
  end)

  t.test("user heading highlights win in the default reading theme", function()
    vim.cmd("hi clear")
    vim.api.nvim_set_hl(0, "MdReadableHeading2", { fg = 0xff0000 })
    theme.setup()
    t.eq(0xff0000, vim.api.nvim_get_hl(0, { name = "MdReadableHeading2" }).fg)
    local s = open({ "# A", "## B" })
    local ns = vim.api.nvim_get_hl_ns({ winid = s.read_win })
    t.eq({}, vim.api.nvim_get_hl(ns, { name = "MdReadableHeading2" }))
    cleanup()
    vim.cmd("hi clear")
    theme.setup()
  end)

  t.test("outline panel shows level markers and per-level highlights", function()
    local s = open({ "# Top", "", "## Middle", "", "### Low" })
    require("md-readable.ui.navigation").outline(s)
    local panel = s._navigation.panels.outline
    local lines = vim.api.nvim_buf_get_lines(panel.buf, 0, -1, false)
    t.ok(vim.tbl_contains(lines, "# Top"))
    t.ok(vim.tbl_contains(lines, "  ## Middle"))
    t.ok(vim.tbl_contains(lines, "    ### Low"))
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(panel.buf, -1, 0, -1, { details = true })) do
      found[mark[4].hl_group or ""] = true
    end
    t.ok(found.MdReadableHeading1 and found.MdReadableHeading2 and found.MdReadableHeading3)
    cleanup()
  end)
  t.test("reading body keeps its width and is centered at 60/80/120/200 columns", function()
    local columns, lines = vim.o.columns, vim.o.lines
    vim.o.lines = 40
    local paragraph = string.rep("word ", 60)
    for _, width in ipairs({ 60, 80, 120, 200 }) do
      vim.o.columns = width
      for _, mode in ipairs({ "float", "vert", "current" }) do
        local s = open({ "# Title", "", paragraph }, mode, { width = 50 })
        vim.cmd("redraw")
        vim.wait(50, function()
          return false
        end)
        vim.cmd("redraw")
        local win_width = vim.api.nvim_win_get_width(s.read_win)
        local info = vim.fn.getwininfo(s.read_win)[1]
        local body = 0
        for _, line in ipairs(vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false)) do
          body = math.max(body, vim.fn.strdisplaywidth(line))
        end
        local label = mode .. "@" .. width
        t.ok(body <= 50, label .. " body width " .. body)
        t.ok(body <= win_width - info.textoff, label .. " body fits")
        local left, right = info.textoff, win_width - info.textoff - body
        -- Neovim caps the status column width (47 cells in 0.12); beyond it the
        -- body stays as far right as the cap allows.
        t.ok(
          math.abs(left - right) <= 2 or (left >= 40 and right > left),
          label .. " centered: " .. left .. "/" .. right
        )
        if mode == "float" then
          t.ok(win_width <= 54, label .. " float width " .. win_width)
          local config = vim.api.nvim_win_get_config(s.read_win)
          local col = type(config.col) == "table" and config.col[false] or config.col
          t.ok(math.abs(col - (width - win_width) / 2) <= 2, label .. " float centered")
        end
        cleanup()
      end
    end
    open({ "text" }, "current", { width = 50, center = false })
    t.eq("", vim.wo.statuscolumn)
    cleanup()
    t.eq("", vim.wo.statuscolumn, "current window option restored")
    vim.o.columns, vim.o.lines = columns, lines
  end)
  t.test("link kind markers are decoration and configurable", function()
    local source = { "[web](https://x.org) [doc](a.md) [top](#top) [file](f.pdf) https://bare.org ![i](p.png)" }
    local function line(icons)
      return render(parse(source), { width = 200, links = { icons = icons } }).lines[1]
    end
    t.eq("web↗ doc→ top# file⧉ https://bare.org [Image: i]", line("unicode"))
    t.eq("web^ doc> top# file* https://bare.org [Image: i]", line("ascii"))
    t.eq("web doc top file https://bare.org [Image: i]", line(false))
    t.eq("web(w) doc→ top# file⧉ https://bare.org [Image: i]", line({ external = "(w)" }))
    local value = render(parse(source), { width = 200, links = { icons = "unicode" } })
    local map = source_map.new(source, value)
    local icon = value.lines[1]:find("↗", 1, true) - 1
    t.eq(nil, map:copy(0, icon, 0, icon + #"↗", "char"), "icon alone copies nothing")
    t.eq("[web](https://x.org)", map:copy(0, 0, 0, icon + #"↗", "char"))
    local s = open(source, "current", { links = { icons = "unicode" } })
    vim.fn.setreg('"', "kept")
    vim.api.nvim_win_set_cursor(s.read_win, { 1, icon })
    vim.cmd("normal yl")
    t.eq("kept", vim.fn.getreg('"'))
    cleanup()
  end)
end
