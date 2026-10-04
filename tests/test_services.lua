return function(t)
  local formatter = require("md-readable.table.format")
  local editor = require("md-readable.table.edit")
  local focus = require("md-readable.reader.focus")
  local theme = require("md-readable.ui.theme")
  local mini = require("md-readable.minimap.render")
  local minimap = require("md-readable.minimap")
  local next_id = 1000
  local function session(lines)
    next_id = next_id + 1
    local original = vim.api.nvim_get_current_win()
    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, lines)
    local read = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(read, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(read, true, { split = "below", win = original })
    local s = {
      id = next_id,
      source_buf = source,
      read_buf = read,
      read_win = win,
      source_win = original,
      config = { focus = {}, minimap = {} },
      rendered = { lines = lines },
      map = {
        to_display = function(_, row, col)
          return row, col
        end,
        to_source = function(_, row, col)
          return row, col
        end,
      },
    }
    s.sync = function(self, from)
      self.synced = from
    end
    s.schedule = function(self)
      self.scheduled = (self.scheduled or 0) + 1
    end
    s.jump_source = function(self, row, col)
      self.jumped = { row, col }
      vim.api.nvim_win_set_cursor(self.read_win, { row + 1, col })
    end
    s.cleanup = function()
      minimap.close(s)
      focus.close(s)
      theme.close(win)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      for _, buf in ipairs({ source, read }) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
    return s
  end
  local function tbl()
    return {
      start_row = 0,
      end_row = 4,
      alignments = { "left", "center", "right" },
      rows = {
        { source_row = 0, cells = { { text = "Name" }, { text = "中" }, { text = "Value" } } },
        { source_row = 2, cells = { { text = "a\\|b" }, { text = "é" }, { text = "`x|y`" } } },
        { source_row = 3, cells = { { text = "last" }, { text = "" }, { text = "5" } } },
      },
    }
  end

  t.test("table format preserves Unicode, inline code, escaped pipes and input", function()
    local input = tbl()
    local saved = vim.deepcopy(input)
    local lines = formatter.format(input)
    t.eq(saved, input)
    t.eq(
      { "| Name | 中  | Value |", "| :--- | :-: | ----: |", "| a\\|b |  é  | `x|y` |", "| last |     |     5 |" },
      lines
    )
    for _, line in ipairs(lines) do
      t.eq(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(line))
    end
  end)

  t.test("table formatting measures tabs at their physical column", function()
    local input = {
      rows = {
        { cells = { { text = "h" }, { text = "h" } } },
        { cells = { { text = "a\tb" }, { text = "中\tend" } } },
      },
      alignments = { "left", "left" },
    }
    local lines = formatter.format(input)
    t.ok(lines[3]:find("a\tb", 1, true))
    for _, line in ipairs(lines) do
      t.eq(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(line))
    end
  end)

  t.test("column insertion and count deletion affect every row", function()
    local input = tbl()
    local added = assert(editor.edit(input, "col_after", 2, 2))
    t.eq("| Name | 中  |     |     | Value |", added[1])
    local removed = assert(editor.edit(input, "col_delete", 1, 2))
    t.eq("| Value |", removed[1])
    t.eq(3, #input.rows[1].cells)
    t.eq(nil, editor.edit(input, "col_delete", 1, 3))
    t.eq(nil, editor.edit(input, "col_after", 4, 1))
    t.eq(nil, editor.edit(input, "col_before", 1, 0))
  end)

  t.test("row boundaries preserve a header and allow an empty data set", function()
    local input = tbl()
    t.eq(6, #assert(editor.edit(input, "row_after", 0, 2)))
    t.eq(2, #assert(editor.edit(input, "row_delete", 1, 2)))
    t.eq(nil, editor.edit(input, "row_delete", 0, 1))
    t.eq(nil, editor.edit(input, "row_before", 0, 1))
    t.eq(nil, editor.edit(input, "row_delete", 2, 2))
  end)

  t.test("focus bounds match Limelight blank-line and span semantics", function()
    local s = session({ "first", "first continued", "", "second", "", "", "third", "" })
    local expected = { { 0, 3 }, { 0, 3 }, { 0, 5 }, { 4, 5 }, { 4, 6 }, { 6, 8 }, { 7, 8 }, { 7, 0 } }
    for row, bounds in ipairs(expected) do
      vim.api.nvim_win_set_cursor(s.read_win, { row, 0 })
      t.eq(bounds, focus.bounds(s.read_win), "row " .. row)
      t.eq({ row, 0 }, vim.api.nvim_win_get_cursor(s.read_win))
    end
    vim.api.nvim_win_set_cursor(s.read_win, { 4, 0 })
    t.eq({ 0, 6 }, focus.bounds(s.read_win, { span = 1 }))
    vim.api.nvim_win_set_cursor(s.read_win, { 5, 0 })
    t.eq({ 4, 6 }, focus.bounds(s.read_win, { span = 1 }))
    s.cleanup()
  end)

  t.test("focus fixed Visual range is window-local and cleans up", function()
    local s = session({ "one", "", "two", "", "three" })
    focus.set(s, true, { start_row = 2, end_row = 3 })
    local before = vim.fn.getmatches(s.read_win)
    t.eq(2, #before)
    t.eq({}, vim.fn.getmatches(s.source_win))
    vim.api.nvim_win_set_cursor(s.read_win, { 5, 0 })
    focus.update(s)
    local after = vim.fn.getmatches(s.read_win)
    t.eq(before[1].pattern, after[1].pattern)
    t.eq(before[2].pattern, after[2].pattern)
    focus.set(s, false)
    t.eq({}, vim.fn.getmatches(s.read_win))
    s.cleanup()
  end)

  t.test("themes remain local and default clears prior palette", function()
    local s = session({ "hello" })
    theme.setup()
    local global = vim.api.nvim_get_hl(0, { name = "Normal" })
    local original_ns = vim.api.nvim_get_hl_ns({ winid = s.read_win })
    local ns = assert(theme.apply(s.read_win, "dark"))
    t.eq(0x20242c, vim.api.nvim_get_hl(ns, { name = "Normal" }).bg)
    t.eq(global, vim.api.nvim_get_hl(0, { name = "Normal" }))
    t.ok(vim.api.nvim_get_hl_ns({ winid = s.source_win }) ~= ns)
    theme.apply(s.read_win, "light")
    t.eq(0xfaf8f2, vim.api.nvim_get_hl(ns, { name = "Normal" }).bg)
    theme.apply(s.read_win, "default")
    t.eq({}, vim.api.nvim_get_hl(ns, { name = "Normal" }))
    theme.close(s.read_win)
    t.eq(original_ns, vim.api.nvim_get_hl_ns({ winid = s.read_win }))
    s.cleanup()
  end)

  t.test("minimap picture fills its width and height without stretching small documents", function()
    local function extent(output)
      local cols = 0
      for _, line in ipairs(output.lines) do
        local cells = vim.fn.split(line, "\\zs")
        for i = #cells, 1, -1 do
          if cells[i] ~= "⠀" and cells[i] ~= " " then
            cols = math.max(cols, i)
            break
          end
        end
      end
      return cols, #output.lines
    end
    local wide = {}
    for i = 1, 130 do
      wide[i] = string.rep("x", 100)
    end
    -- 100 columns into 24 dots and 130 rows into 120 dots: a whole-number stride
    -- left 2 cells and 13 rows empty.
    t.eq({ 12, 30 }, { extent(mini.render(wide, { width = 12, height = 30 })) })
    t.eq({ 12, 30 }, { extent(mini.render(wide, { width = 12, height = 30, mode = "ascii" })) })
    t.eq({ 5, 1 }, { extent(mini.render({ string.rep("x", 10) }, { width = 12, height = 30 })) })
  end)

  t.test("Braille covers eight dots and ASCII preserves source mapping", function()
    local output = mini.render({ "xx", "xx", "xx", "xx" }, { width = 1, height = 1 })
    t.eq({ "⣿" }, output.lines)
    t.eq({ 0, 0, 0, 0 }, output.display_to_mini)
    t.eq({ 0 }, output.mini_to_display)
    local ascii = mini.render({ "中\tx", "é", "", "z" }, { width = 4, height = 2, mode = "ascii" })
    t.eq(2, #ascii.lines)
    t.eq({ 0, 0, 1, 1 }, ascii.display_to_mini)
    for _, line in ipairs(ascii.lines) do
      t.eq(4, vim.fn.strdisplaywidth(line))
    end
  end)

  t.test("minimap is only the picture and closes its nofile buffer cleanly", function()
    theme.setup()
    local s = session({ "a", "b", "c", "d", "e" })
    local win = assert(minimap.open(s))
    local buf = vim.api.nvim_win_get_buf(win)
    t.eq("nofile", vim.bo[buf].buftype)
    -- No annotation lanes: every cell of the window is picture.
    local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    t.eq(vim.api.nvim_win_get_width(win), vim.fn.strdisplaywidth(first))
    local cell = vim.fn.char2nr(vim.fn.strcharpart(first, 0, 1))
    t.ok(cell > 0x2800 and cell <= 0x28FF, "first column draws the document")
    minimap.focus(s)
    vim.api.nvim_win_set_cursor(win, { 2, 0 })
    local keys = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
    vim.api.nvim_feedkeys(keys, "xt", false)
    t.eq({ 4, 0 }, s.jumped)
    minimap.close(s)
    t.ok(not vim.api.nvim_win_is_valid(win))
    t.ok(not vim.api.nvim_buf_is_valid(buf))
    s.cleanup()
  end)

  t.test("minimap supports floating readers without exceeding their width budget", function()
    local s = session({ "a", "b", "c" })
    vim.api.nvim_win_set_config(s.read_win, { relative = "editor", row = 1, col = 1, width = 50, height = 10 })
    local original = vim.api.nvim_win_get_width(s.read_win)
    local win = assert(minimap.open(s))
    t.eq("win", vim.api.nvim_win_get_config(win).relative)
    t.ok(vim.api.nvim_win_get_width(win) + vim.api.nvim_win_get_width(s.read_win) + 2 <= original)
    minimap.update(s)
    minimap.close(s)
    t.eq(original, vim.api.nvim_win_get_width(s.read_win))
    vim.api.nvim_win_set_config(s.read_win, { width = 25 })
    local before = #vim.api.nvim_list_wins()
    t.eq(nil, minimap.open(s))
    t.eq(before, #vim.api.nvim_list_wins())
    s.cleanup()
  end)
end
