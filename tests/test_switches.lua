return function(t)
  local api = require("md-readable")
  local config = require("md-readable.config")
  local sessions = require("md-readable.reader.session")
  local minimap = require("md-readable.minimap")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  local function open(lines, mode, opts)
    cleanup()
    api.setup(vim.tbl_deep_extend("force", {
      navigation = { auto_open = false },
      images = { enable = false },
      debounce = 0,
    }, opts or {}))
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return api.open(mode or "current")
  end
  local function groups(rendered)
    local found = {}
    for _, h in ipairs(rendered.highlights) do
      found[h.group] = true
    end
    return found
  end

  t.test("feature switches default to on and accept the former enabled key", function()
    local value = config.setup({})
    for _, name in ipairs({ "links", "table", "focus", "minimap", "images", "mermaid" }) do
      t.eq(true, value[name].enable, name)
    end
    value = config.setup({ images = { enabled = false }, mermaid = { enabled = false } })
    t.eq(false, value.images.enable)
    t.eq(false, value.mermaid.enable)
    t.eq(nil, value.images.enabled)
    value = config.setup({ images = { enable = true, enabled = false } })
    t.eq(true, value.images.enable, "explicit enable wins")
    local ok, err = pcall(config.setup, { focus = { enable = "yes" } })
    t.ok(not ok and err:find("focus.enable must be true or false", 1, true), err)
    config.setup({})
  end)

  t.test("links.enable = false shows labels as plain text without markers", function()
    local lines = { "[Doc](a.md) and [Site](https://example.com)" }
    local on = render(parse(lines), { links = { enable = true, icons = "unicode" } })
    t.eq("Doc→ and Site↗", on.lines[1])
    t.ok(groups(on).MdReadableLink)
    local off = render(parse(lines), { links = { enable = false, icons = "unicode" } })
    t.eq("Doc and Site", off.lines[1])
    t.ok(not groups(off).MdReadableLink)
    t.ok(not groups(off).MdReadableLinkIcon)
    local nodes = 0
    for _, segment in ipairs(off.segments) do
      if segment.kind == "node" then
        nodes = nodes + 1
      end
    end
    t.eq(2, nodes, "links still map to their source for copying and following")
  end)

  t.test("table.enable = false shows the Markdown source rows", function()
    local lines = { "| a | b |", "|---|---|", "| 1 | 2 |" }
    local value = render(parse(lines), { table = { enable = false } })
    t.eq(lines, value.lines)
    t.eq({ 0, 1, 2 }, value.row_map)
    t.eq(0, #value.cells)
  end)

  t.test("focus and minimap start with the reading view unless disabled", function()
    local s = open({ "# Title", "", "text" }, "current")
    t.eq(true, s.focus_enabled)
    t.ok(minimap.get(s), "minimap opened")
    s = open({ "# Title", "", "text" }, "current", { focus = { enable = false }, minimap = { enable = false } })
    t.ok(not s.focus_enabled)
    t.eq(nil, minimap.get(s))
    cleanup()
  end)

  t.test("reading body is refitted after the minimap takes columns", function()
    local columns, lines = vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 60, 40
    for _, mode in ipairs({ "float", "vert", "current" }) do
      local s = open({ "# Title", "", string.rep("word ", 60) }, mode, { width = 50 })
      t.ok(minimap.get(s), mode .. " minimap opened")
      vim.wait(100, function()
        return false
      end)
      local body = 0
      for _, line in ipairs(vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false)) do
        body = math.max(body, vim.fn.strdisplaywidth(line))
      end
      local info = vim.fn.getwininfo(s.read_win)[1]
      t.ok(body <= vim.api.nvim_win_get_width(s.read_win) - info.textoff, mode .. " body width " .. body)
    end
    cleanup()
    vim.o.columns, vim.o.lines = columns, lines
  end)
end
