return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local minimap = require("md-readable.minimap")
  local mini_render = require("md-readable.minimap.render")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  local function open(lines, opts)
    cleanup()
    api.setup(vim.tbl_deep_extend("force", {
      navigation = { auto_open = false },
      images = { enable = false },
      debounce = 0,
    }, opts or {}))
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return api.open("vert")
  end

  t.test("headings and code blocks are projected onto minimap rows", function()
    local reading = render(parse({ "# Title", "", "text", "", "```lua", "local x = 1", "```", "", "## Next" }), {})
    local mini = mini_render.render(reading.lines, { width = 12, height = 40, mode = "ascii" })
    local regions = mini_render.regions(reading, mini)
    t.eq("MdReadableHeading1", regions[mini.display_to_mini[1]])
    local code = reading.code_blocks[1]
    t.eq("MdReadableMinimapCode", regions[mini.display_to_mini[code.row + 2]])
    local next_row
    for index, line in ipairs(reading.lines) do
      if line == "Next" then
        next_row = index
      end
    end
    t.eq("MdReadableHeading2", regions[mini.display_to_mini[next_row]])
    t.eq(nil, regions[mini.display_to_mini[3]], "plain text stays uncolored")
    -- In Braille mode four display rows share one minimap row; the heading wins.
    local packed = mini_render.render(reading.lines, { width = 12, height = 40 })
    t.eq("MdReadableHeading1", mini_render.regions(reading, packed)[0])
  end)

  t.test("minimap colors heading and code rows in its buffer", function()
    local s = open({ "# Title", "", "```lua", "local x = 1", "```" })
    local state = assert(minimap.get(s))
    local groups = {}
    local ns = vim.api.nvim_get_namespaces().MdReadableMinimap
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(state.buf, ns, 0, -1, { details = true })) do
      if mark[4].hl_group then
        groups[mark[4].hl_group] = mark[3]
      end
    end
    t.eq(0, groups.MdReadableHeading1, "colored from the first column")
    t.ok(vim.fn.hlexists("MdReadableMinimapCode") == 1)
    cleanup()
  end)

  t.test("layout plugins never see the minimap before its filetype and fixed width", function()
    -- windows.nvim resizes on BufWinEnter and skips windows by filetype or
    -- 'winfixwidth'; an anonymous scratch window there gets resized.
    local group = vim.api.nvim_create_augroup("MdReadableTestLayout", { clear = true })
    local anonymous = 0
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      callback = function(args)
        if vim.bo[args.buf].buftype == "nofile" and vim.bo[args.buf].filetype == "" then
          anonymous = anonymous + 1
        end
      end,
    })
    local s = open({ "# Title", "", "text" })
    vim.api.nvim_del_augroup_by_id(group)
    local state = assert(minimap.get(s))
    t.eq(0, anonymous)
    t.eq("md-readable-minimap", vim.bo[state.buf].filetype)
    t.ok(vim.wo[state.win].winfixwidth)
    cleanup()
  end)

  t.test("moving in the minimap moves the reading view and keeps the minimap focused", function()
    local lines = {}
    for i = 1, 300 do
      lines[i] = i % 10 == 1 and ("# Heading " .. i) or ("line " .. i)
    end
    local s = open(lines)
    local state = assert(minimap.get(s))
    vim.api.nvim_set_current_win(state.win)
    local last = #vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    vim.api.nvim_win_set_cursor(state.win, { last, 2 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.buf })
    local display = state.rendered.mini_to_display[last]
    t.eq(display + 1, vim.api.nvim_win_get_cursor(s.read_win)[1])
    t.eq(state.win, vim.api.nvim_get_current_win(), "focus stays in the minimap")
    local source_row = s.map:to_source(display, 0)
    t.eq(source_row + 1, vim.api.nvim_win_get_cursor(s.source_win)[1], "source window follows")
    -- Moving within the minimap row the reader is already in does not move it.
    vim.api.nvim_win_set_cursor(s.read_win, { display + 2, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.buf })
    t.eq(display + 2, vim.api.nvim_win_get_cursor(s.read_win)[1])
    cleanup()
  end)

  t.test("minimap.follow = false keeps the reading view until Enter", function()
    local lines = {}
    for i = 1, 300 do
      lines[i] = "line " .. i
    end
    local s = open(lines, { minimap = { follow = false } })
    local state = assert(minimap.get(s))
    vim.api.nvim_set_current_win(state.win)
    local before = vim.api.nvim_win_get_cursor(s.read_win)[1]
    vim.api.nvim_win_set_cursor(state.win, { #vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.buf })
    t.eq(before, vim.api.nvim_win_get_cursor(s.read_win)[1])
    cleanup()
  end)

  t.test("moving over a heading in a navigation panel follows it; pages wait for Enter", function()
    local navigation = require("md-readable.ui.navigation")
    local lines = {}
    for i = 1, 6 do
      vim.list_extend(lines, { "# Heading " .. i, "" })
      for j = 1, 30 do
        lines[#lines + 1] = "text " .. i .. "." .. j
      end
      lines[#lines + 1] = ""
    end
    for _, follow in ipairs({ true, false }) do
      local s = open(lines, { navigation = { follow = follow }, minimap = { enable = false } })
      navigation.outline(s)
      local panel = s._navigation.panels.outline
      t.eq(panel.win, vim.api.nvim_get_current_win())
      local target
      for index, entry in ipairs(panel.entries) do
        if entry.kind == "heading" and entry.heading.title == "Heading 5" then
          target = index
        end
      end
      local before = vim.api.nvim_win_get_cursor(s.read_win)[1]
      vim.api.nvim_win_set_cursor(panel.win, { assert(target), 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = panel.buf })
      local heading = s.map:to_display(panel.entries[target].heading.range.start.row, 0)
      if follow then
        t.eq(heading + 1, vim.api.nvim_win_get_cursor(s.read_win)[1], "reader at Heading 5")
        t.eq(panel.win, vim.api.nvim_get_current_win(), "focus stays in the panel")
      else
        t.eq(before, vim.api.nvim_win_get_cursor(s.read_win)[1], "follow = false waits for Enter")
      end
      cleanup()
    end
  end)
end
