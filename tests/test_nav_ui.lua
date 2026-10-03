return function(t)
  local UI = require('md-readable.ui.navigation')
  local function with_session(columns, layout, callback)
    local original = { columns = vim.o.columns, lines = vim.o.lines, tab = vim.api.nvim_get_current_tabpage(), statusline = vim.o.statusline }
    vim.o.columns, vim.o.lines = columns, 24
    vim.cmd('tabnew')
    local tab = vim.api.nvim_get_current_tabpage()
    local root = t.tempdir()
    t.write(root .. '/one.md', { '# Intro', 'body', '## Child', 'text', '# End' })
    t.write(root .. '/two.md', { '# Next' })
    local source = vim.fn.bufadd(root .. '/one.md'); vim.fn.bufload(source)
    local read = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(read, 0, -1, false, { 'Intro', 'body', 'Child', 'text', 'End' })
    vim.api.nvim_win_set_buf(0, read)
    local win = vim.api.nvim_get_current_win()
    vim.o.statusline = 'user statusline'
    local one = { id = 'one', title = '第一章 とても長い日本語の題名がここにあります', children = {}, target = { type = 'document', path = 'one.md' } }
    local two = { id = 'two', title = 'Next chapter', children = {}, target = { type = 'document', path = 'two.md' } }
    local session = { config = { layout = layout or 'integrated', navigation = { width = 28, min_body_width = 48 } },
      source_buf = source, read_buf = read, read_win = win, generation = 1,
      document = { path = root .. '/one.md', headings = {
        { id = 'intro', title = 'Introduction', level = 1, range = { start = { row = 0 } } },
        { id = 'child', title = 'Child', level = 2, range = { start = { row = 2 } } },
        { id = 'end', title = 'End', level = 1, range = { start = { row = 4 } } },
      } },
      snapshot = { schemaVersion = 1, rootDir = root, adapterId = 'test', orderOrigin = 'custom', diagnostics = {}, trees = { { id = 'main', title = 'Main book', items = { one, two } }, { id = 'other', title = 'Other book', items = { two } } } },
    }
    function session.map_to_source(_, row, col) return row, col end
    session.map = { to_source = session.map_to_source }
    function session:jump_source(row) self.jumped = row; vim.api.nvim_win_set_cursor(self.read_win, { row + 1, 0 }) end
    function session:navigate(path, anchor) self.navigated = { path, anchor }; self.document.path = path end
    function session:refresh() UI.update(self) end
    function session:load_navigation() self.loaded = true end
    local ok, err = xpcall(function() callback(session, root) end, debug.traceback)
    UI.close(session)
    if vim.api.nvim_tabpage_is_valid(tab) then vim.api.nvim_set_current_tabpage(tab); vim.cmd('tabclose!') end
    if vim.api.nvim_buf_is_valid(source) then vim.api.nvim_buf_delete(source, { force = true }) end
    if vim.api.nvim_buf_is_valid(read) then vim.api.nvim_buf_delete(read, { force = true }) end
    vim.o.columns, vim.o.lines, vim.o.statusline = original.columns, original.lines, original.statusline
    if vim.api.nvim_tabpage_is_valid(original.tab) then vim.api.nvim_set_current_tabpage(original.tab) end
    if not ok then error(err) end
  end
  local function key(panel, name)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(panel.buf, 'n')) do
      if mapping.lhs == name then mapping.callback(); return end
    end
    error('missing mapping ' .. name)
  end
  local function select_entry(panel, predicate)
    for i, entry in ipairs(panel.entries) do if predicate(entry) then vim.api.nvim_win_set_cursor(panel.win, { i, 0 }); return entry end end
    error('entry not found')
  end
  t.test('80x24 integrated tree preserves body width, native statusline and focus', function()
    with_session(80, 'integrated', function(s)
      local win = UI.open(s)
      t.ok(win); t.eq(s.read_win, vim.api.nvim_get_current_win())
      t.ok(vim.api.nvim_win_get_width(s.read_win) >= 48)
      t.eq('user statusline', vim.o.statusline)
      local panel = s._navigation.panels.book
      local lines = vim.api.nvim_buf_get_lines(panel.buf, 0, -1, false)
      for _, line in ipairs(lines) do t.ok(vim.fn.strdisplaywidth(line) <= 28) end
      t.ok(table.concat(lines, '\n'):find('Introduction', 1, true))
      t.eq(false, vim.api.nvim_win_get_config(s._navigation.pager.win).focusable)
      t.ok(vim.api.nvim_buf_is_valid(s.source_buf))
    end)
  end)
  t.test('60-column reader remains full width until navigation is explicitly summoned', function()
    with_session(60, 'integrated', function(s)
      t.eq(nil, UI.open(s)); t.eq(60, vim.api.nvim_win_get_width(s.read_win))
      UI.toggle(s)
      local panel = s._navigation.panels.book
      t.eq('editor', vim.api.nvim_win_get_config(panel.win).relative)
      t.eq(panel.win, vim.api.nvim_get_current_win())
      key(panel, 'q'); t.eq(s.read_win, vim.api.nvim_get_current_win()); t.eq(nil, s._navigation.panels.book)
      t.ok(vim.api.nvim_buf_is_valid(s.source_buf))
    end)
  end)
  t.test('120-column separate layout provides independent book and outline panels', function()
    with_session(120, 'separate', function(s)
      UI.open(s)
      t.ok(s._navigation.panels.book); t.ok(s._navigation.panels.outline)
      t.ok(vim.api.nvim_win_get_width(s.read_win) >= 48)
      local book_text = table.concat(vim.api.nvim_buf_get_lines(s._navigation.panels.book.buf, 0, -1, false), '\n')
      t.eq(nil, book_text:find('Introduction', 1, true))
      local outline_text = table.concat(vim.api.nvim_buf_get_lines(s._navigation.panels.outline.buf, 0, -1, false), '\n')
      t.ok(outline_text:find('Introduction', 1, true))
      t.eq(s.read_win, vim.api.nvim_get_current_win())
    end)
  end)
  t.test('ondemand layout opens only on command and Enter returns to body', function()
    with_session(120, 'ondemand', function(s)
      t.eq(nil, UI.open(s)); UI.toggle(s)
      local panel = s._navigation.panels.book
      select_entry(panel, function(entry) return entry.kind == 'heading' and entry.id == 'heading:child' end)
      key(panel, '<CR>'); t.eq(2, s.jumped); t.eq(s.read_win, vim.api.nvim_get_current_win())
      t.eq(nil, s._navigation.panels.book)
    end)
  end)
  t.test('navigation selection does not move body and refresh never steals chooser cursor', function()
    with_session(80, 'integrated', function(s)
      UI.open(s); local panel = s._navigation.panels.book
      vim.api.nvim_set_current_win(panel.win)
      select_entry(panel, function(entry) return entry.id == 'two' end)
      local selected = vim.api.nvim_win_get_cursor(panel.win)
      vim.api.nvim_win_set_cursor(s.read_win, { 3, 0 })
      UI.update(s)
      t.eq(selected, vim.api.nvim_win_get_cursor(panel.win)); t.eq(nil, s.navigated); t.eq(nil, s.jumped)
      local tick = vim.api.nvim_buf_get_changedtick(panel.buf)
      UI.update(s); t.eq(tick, vim.api.nvim_buf_get_changedtick(panel.buf))
    end)
  end)
  t.test('h/l collapse survives document rerender and expands again', function()
    with_session(80, 'integrated', function(s)
      UI.open(s); local panel = s._navigation.panels.book
      vim.api.nvim_set_current_win(panel.win)
      select_entry(panel, function(entry) return entry.id == 'heading:intro' end)
      key(panel, 'h'); t.eq(true, s._navigation.collapsed['heading:intro'])
      s.generation = s.generation + 1; UI.update(s)
      local found = false; for _, entry in ipairs(panel.entries) do if entry.id == 'heading:child' then found = true end end
      t.eq(false, found)
      key(panel, 'l'); t.eq(false, s._navigation.collapsed['heading:intro'])
      found = false; for _, entry in ipairs(panel.entries) do if entry.id == 'heading:child' then found = true end end
      t.eq(true, found)
    end)
  end)
  t.test('previous/next uses book reading order and never wraps at boundaries', function()
    with_session(80, 'integrated', function(s, root)
      UI.open(s)
      t.eq(false, UI.move(s, 'prev')); t.eq(nil, s.navigated)
      t.eq(true, UI.move(s, 'next')); t.eq(root .. '/two.md', s.navigated[1])
      t.eq(false, UI.move(s, 'next')); t.eq(true, UI.move(s, 'prev')); t.eq(root .. '/one.md', s.navigated[1])
      s.document.path = root .. '/unlisted.md'; t.eq(false, UI.move(s, 'next'))
    end)
  end)
  t.test('tree choice and ambiguous adapter selection use the UI boundary', function()
    with_session(80, 'integrated', function(s)
      UI.open(s)
      local original = vim.ui.select
      vim.ui.select = function(items, _, done) done(items[2]) end
      UI.select(s); t.eq('other', s.tree_id)
      s.nav_result = { status = 'ambiguous', candidates = { { adapter_id = 'mkdocs', root_dir = '/tmp/project', evidence = { 'mkdocs.yml' } }, { adapter_id = 'zensical', root_dir = '/tmp/project', evidence = { 'mkdocs.yml' } } } }
      UI.select(s); vim.ui.select = original
      t.eq('zensical', s.config.adapters.adapter); t.eq('/tmp/project', s.config.adapters.root_dir); t.eq(true, s.loaded)
    end)
  end)
  t.test('outline works without a book and cleanup removes owned windows/buffers', function()
    with_session(60, 'integrated', function(s)
      s.snapshot = nil; UI.outline(s)
      local panel = s._navigation.panels.outline
      t.ok(panel); local buf, win = panel.buf, panel.win
      UI.close(s); t.eq(false, vim.api.nvim_win_is_valid(win)); t.eq(false, vim.api.nvim_buf_is_valid(buf))
      t.eq(nil, s._navigation.group); t.ok(vim.api.nvim_buf_is_valid(s.source_buf))
    end)
  end)
  t.test('resize to narrow width hides automatic sidebar and preserves source/read windows', function()
    with_session(120, 'integrated', function(s)
      UI.open(s); t.ok(s._navigation.panels.book)
      vim.o.columns = 60
      vim.api.nvim_exec_autocmds('VimResized', {})
      vim.wait(50, function() return s._navigation.panels.book == nil end, 5)
      t.eq(nil, s._navigation.panels.book); t.ok(vim.api.nvim_win_is_valid(s.read_win))
      t.ok(vim.api.nvim_buf_is_valid(s.source_buf))
    end)
  end)
  t.test('stale reparse preserves tree with visible marker and keeps user source split', function()
    with_session(180, 'integrated', function(s)
      vim.cmd('leftabove vsplit')
      local source_win = vim.api.nvim_get_current_win(); vim.api.nvim_win_set_buf(source_win, s.source_buf)
      vim.api.nvim_set_current_win(s.read_win)
      UI.open(s); s.stale = true; UI.update(s)
      local panel = s._navigation.panels.book
      local text = table.concat(vim.api.nvim_buf_get_lines(panel.buf, 0, -1, false), '\n')
      t.ok(text:find('Stale', 1, true))
      local pager = vim.api.nvim_buf_get_lines(s._navigation.pager.buf, 0, -1, false)[1]
      t.ok(pager:find('[stale]', 1, true))
      UI.close(s)
      t.ok(vim.api.nvim_win_is_valid(source_win)); t.eq(s.source_buf, vim.api.nvim_win_get_buf(source_win))
    end)
  end)
end
