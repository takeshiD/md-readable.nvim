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
end
