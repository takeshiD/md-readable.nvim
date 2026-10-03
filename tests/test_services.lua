return function(t)
  local formatter = require('md-readable.table.format')
  local editor = require('md-readable.table.edit')
  local focus = require('md-readable.reader.focus')
  local theme = require('md-readable.ui.theme')
  local mini = require('md-readable.minimap.render')
  local minimap = require('md-readable.nav.minimap')
  local git = require('md-readable.minimap.git')
  local diagnostic = require('md-readable.minimap.diagnostic')
  local next_id = 1000
  local function session(lines)
    next_id = next_id + 1
    local original = vim.api.nvim_get_current_win()
    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, lines)
    local read = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(read, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(read, true, { split = 'below', win = original })
    local s = { id = next_id, source_buf = source, read_buf = read, read_win = win, source_win = original,
      config = { focus = {}, minimap = { git = false, diagnostic = false } }, rendered = { lines = lines },
      map = { to_display = function(_, row, col) return row, col end, to_source = function(_, row, col) return row, col end } }
    s.jump_source = function(self, row, col) self.jumped = { row, col }; vim.api.nvim_win_set_cursor(self.read_win, { row + 1, col }) end
    s.cleanup = function()
      minimap.close(s); focus.close(s); theme.close(win)
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      for _, buf in ipairs({ source, read }) do if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end end
    end
    return s
  end
  local function tbl()
    return { start_row = 0, end_row = 4, alignments = { 'left', 'center', 'right' }, rows = {
      { source_row = 0, cells = { { text = 'Name' }, { text = '中' }, { text = 'Value' } } },
      { source_row = 2, cells = { { text = 'a\\|b' }, { text = 'é' }, { text = '`x|y`' } } },
      { source_row = 3, cells = { { text = 'last' }, { text = '' }, { text = '5' } } },
    } }
  end

  t.test('table format preserves Unicode, inline code, escaped pipes and input', function()
    local input = tbl()
    local saved = vim.deepcopy(input)
    local lines = formatter.format(input)
    t.eq(saved, input)
    t.eq({ '| Name | 中  | Value |', '| :--- | :-: | ----: |', '| a\\|b |  é  | `x|y` |', '| last |     |     5 |' }, lines)
    for _, line in ipairs(lines) do t.eq(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(line)) end
  end)

  t.test('table formatting measures tabs at their physical column', function()
    local input = { rows = { { cells = { { text = 'h' }, { text = 'h' } } },
      { cells = { { text = 'a\tb' }, { text = '中\tend' } } } }, alignments = { 'left', 'left' } }
    local lines = formatter.format(input)
    t.ok(lines[3]:find('a\tb', 1, true))
    for _, line in ipairs(lines) do t.eq(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(line)) end
  end)

  t.test('column insertion and count deletion affect every row', function()
    local input = tbl()
    local added = assert(editor.edit(input, 'col_after', 2, 2))
    t.eq('| Name | 中  |     |     | Value |', added[1])
    local removed = assert(editor.edit(input, 'col_delete', 1, 2))
    t.eq('| Value |', removed[1])
    t.eq(3, #input.rows[1].cells)
    t.eq(nil, editor.edit(input, 'col_delete', 1, 3))
    t.eq(nil, editor.edit(input, 'col_after', 4, 1))
    t.eq(nil, editor.edit(input, 'col_before', 1, 0))
  end)

  t.test('row boundaries preserve a header and allow an empty data set', function()
    local input = tbl()
    t.eq(6, #assert(editor.edit(input, 'row_after', 0, 2)))
    t.eq(2, #assert(editor.edit(input, 'row_delete', 1, 2)))
    t.eq(nil, editor.edit(input, 'row_delete', 0, 1))
    t.eq(nil, editor.edit(input, 'row_before', 0, 1))
    t.eq(nil, editor.edit(input, 'row_delete', 2, 2))
  end)

  t.test('focus bounds match Limelight blank-line and span semantics', function()
    local s = session({ 'first', 'first continued', '', 'second', '', '', 'third', '' })
    local expected = { { 0, 3 }, { 0, 3 }, { 0, 5 }, { 4, 5 }, { 4, 6 }, { 6, 8 }, { 7, 8 }, { 7, 0 } }
    for row, bounds in ipairs(expected) do
      vim.api.nvim_win_set_cursor(s.read_win, { row, 0 })
      t.eq(bounds, focus.bounds(s.read_win), 'row ' .. row)
      t.eq({ row, 0 }, vim.api.nvim_win_get_cursor(s.read_win))
    end
    vim.api.nvim_win_set_cursor(s.read_win, { 4, 0 })
    t.eq({ 0, 6 }, focus.bounds(s.read_win, { span = 1 }))
    vim.api.nvim_win_set_cursor(s.read_win, { 5, 0 })
    t.eq({ 4, 6 }, focus.bounds(s.read_win, { span = 1 }))
    s.cleanup()
  end)

  t.test('focus fixed Visual range is window-local and cleans up', function()
    local s = session({ 'one', '', 'two', '', 'three' })
    focus.set(s, true, { start_row = 2, end_row = 3 })
    local before = vim.fn.getmatches(s.read_win)
    t.eq(2, #before)
    t.eq({}, vim.fn.getmatches(s.source_win))
    vim.api.nvim_win_set_cursor(s.read_win, { 5, 0 }); focus.update(s)
    local after = vim.fn.getmatches(s.read_win)
    t.eq(before[1].pattern, after[1].pattern)
    t.eq(before[2].pattern, after[2].pattern)
    focus.set(s, false); t.eq({}, vim.fn.getmatches(s.read_win))
    s.cleanup()
  end)

  t.test('themes remain local and default clears prior palette', function()
    local s = session({ 'hello' })
    theme.setup()
    local global = vim.api.nvim_get_hl(0, { name = 'Normal' })
    local original_ns = vim.api.nvim_get_hl_ns({ winid = s.read_win })
    local ns = assert(theme.apply(s.read_win, 'dark'))
    t.eq(0x20242c, vim.api.nvim_get_hl(ns, { name = 'Normal' }).bg)
    t.eq(global, vim.api.nvim_get_hl(0, { name = 'Normal' }))
    t.ok(vim.api.nvim_get_hl_ns({ winid = s.source_win }) ~= ns)
    theme.apply(s.read_win, 'light'); t.eq(0xfaf8f2, vim.api.nvim_get_hl(ns, { name = 'Normal' }).bg)
    theme.apply(s.read_win, 'default'); t.eq({}, vim.api.nvim_get_hl(ns, { name = 'Normal' }))
    theme.close(s.read_win); t.eq(original_ns, vim.api.nvim_get_hl_ns({ winid = s.read_win }))
    s.cleanup()
  end)

  t.test('Braille covers eight dots and ASCII preserves source mapping', function()
    local output = mini.render({ 'xx', 'xx', 'xx', 'xx' }, { width = 1, height = 1 })
    t.eq({ '⣿' }, output.lines)
    t.eq({ 0, 0, 0, 0 }, output.display_to_mini)
    t.eq({ 0 }, output.mini_to_display)
    local ascii = mini.render({ '中\tx', 'é', '', 'z' }, { width = 4, height = 2, mode = 'ascii' })
    t.eq(2, #ascii.lines)
    t.eq({ 0, 0, 1, 1 }, ascii.display_to_mini)
    for _, line in ipairs(ascii.lines) do t.eq(4, vim.fn.strdisplaywidth(line)) end
  end)

  t.test('annotations use SourceMap and most severe diagnostic wins', function()
    local output = mini.render({ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h' }, { width = 2, height = 2 })
    local map = { to_display = function(_, row) return row * 2 end }
    local projected = mini.annotations({ { start_row = 2, end_row = 3, severity = 4 },
      { start_row = 3, end_row = 4, severity = 1 } }, map, output)
    t.eq(nil, projected[0]); t.eq(1, projected[1].severity)
  end)

  t.test('minimap closes its nofile buffer and providers cleanly', function()
    theme.setup()
    local s = session({ 'a', 'b', 'c', 'd', 'e' })
    local win = assert(minimap.open(s))
    local buf = vim.api.nvim_win_get_buf(win)
    t.eq('nofile', vim.bo[buf].buftype)
    minimap.set_annotations(s, 'git', { { start_row = 0, end_row = 1, kind = 'add' } })
    minimap.set_annotations(s, 'diagnostic', { { start_row = 0, end_row = 1, kind = 'diagnostic', severity = 1 } })
    t.eq('+E', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:sub(1, 2))
    minimap.set_annotations(s, 'git', {})
    t.eq(' E', vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:sub(1, 2))
    minimap.focus(s)
    vim.api.nvim_win_set_cursor(win, { 2, 0 })
    local keys = vim.api.nvim_replace_termcodes('<CR>', true, false, true)
    vim.api.nvim_feedkeys(keys, 'xt', false)
    t.eq({ 4, 0 }, s.jumped)
    minimap.close(s)
    t.ok(not vim.api.nvim_win_is_valid(win)); t.ok(not vim.api.nvim_buf_is_valid(buf))
    s.cleanup()
  end)

  t.test('Git diff handles index equality, additions, changes and deletions', function()
    t.eq({}, git.diff('a\nb\n', 'a\nb\n', 2))
    t.eq({ { start_row = 1, end_row = 2, kind = 'add' } }, git.diff('a\n', 'a\nb\n', 2))
    t.eq({ { start_row = 1, end_row = 2, kind = 'change' } }, git.diff('a\nb\n', 'a\nc\n', 2))
    t.eq({ { start_row = 0, end_row = 1, kind = 'delete' } }, git.diff('a\nb\n', 'a\n', 1))
  end)

  t.test('minimap supports floating readers without exceeding their width budget', function()
    local s = session({ 'a', 'b', 'c' })
    vim.api.nvim_win_set_config(s.read_win, { relative = 'editor', row = 1, col = 1, width = 50, height = 10 })
    local original = vim.api.nvim_win_get_width(s.read_win)
    local win = assert(minimap.open(s))
    t.eq('win', vim.api.nvim_win_get_config(win).relative)
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

  t.test('diagnostics filter severity and update/clear standard diagnostic source', function()
    local s = session({ 'a', 'b', 'c' })
    local ns = vim.api.nvim_create_namespace('ServiceTestDiagnostics')
    vim.diagnostic.set(ns, s.source_buf, { { lnum = 0, col = 0, severity = 1, message = 'error' },
      { lnum = 2, col = 0, severity = 4, message = 'hint' } })
    t.eq(2, #diagnostic.collect(s.source_buf))
    t.eq(1, #diagnostic.collect(s.source_buf, { min = vim.diagnostic.severity.WARN }))
    local events = {}
    diagnostic.attach(s, function(_, provider, items) events[#events + 1] = { provider, items } end)
    t.eq(2, #events[#events][2])
    vim.diagnostic.reset(ns, s.source_buf)
    t.eq({}, events[#events][2])
    diagnostic.close(s); s.cleanup()
  end)

  t.test('async Git compares unsaved buffer to index without writes and clears after staging', function()
    local dir = t.tempdir()
    local path = dir .. '/space ; file.md'
    t.write(path, { 'original' })
    local function command(args)
      local result = vim.system(args, { text = true }):wait()
      t.eq(0, result.code, result.stderr)
    end
    command({ 'git', '-C', dir, 'init', '--quiet' })
    command({ 'git', '-C', dir, 'add', '--', path })
    local s = session({ 'unsaved' })
    vim.api.nvim_buf_set_name(s.source_buf, path)
    local events = {}
    git.attach(s, function(_, _, items) events[#events + 1] = items end)
    t.ok(vim.wait(3000, function() return #events > 0 end, 20), 'Git initial diff timed out')
    t.eq('change', events[#events][1].kind)
    t.eq({ 'original' }, vim.fn.readfile(path))
    t.write(path, { 'unsaved' })
    command({ 'git', '-C', dir, 'add', '--', path })
    t.ok(vim.wait(4000, function() return #events > 1 end, 20), 'index watcher did not detect staging')
    t.eq({}, events[#events])
    local before = #events
    vim.api.nvim_buf_set_lines(s.source_buf, 0, -1, false, { 'original' }); git.update(s)
    t.ok(vim.wait(3000, function() return #events > before end, 20))
    t.eq('change', events[#events][1].kind)
    git.close(s); s.cleanup()
  end)
end
