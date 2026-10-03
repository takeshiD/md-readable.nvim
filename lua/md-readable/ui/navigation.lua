local C = require('md-readable.adapters.common')
local Index = require('md-readable.navigation.index')
local Order = require('md-readable.navigation.order')
local M = {}
local namespace = vim.api.nvim_create_namespace('md-readable-navigation')
local next_id = 0

local function valid(win) return win and vim.api.nvim_win_is_valid(win) end
local function clip(text, width)
  text = tostring(text or ''):gsub('[\r\n\t]', ' ')
  if vim.fn.strdisplaywidth(text) <= width then return text end
  if width < 4 then return string.rep('.', math.max(0, width)) end
  local out = ''
  for _, char in ipairs(vim.fn.split(text, '\\zs')) do
    if vim.fn.strdisplaywidth(out .. char) > width - 3 then break end
    out = out .. char
  end
  return out .. '...'
end
local function state(session)
  if not session._navigation then
    next_id = next_id + 1
    session._navigation = { id = next_id, collapsed = {}, collapsed_trees = {}, history = {}, panels = {}, order = {}, open = false, revision = 0 }
  end
  return session._navigation
end
local function current_path(session)
  return session.document and session.document.path or (session.source_buf and vim.api.nvim_buf_is_valid(session.source_buf) and vim.api.nvim_buf_get_name(session.source_buf)) or ''
end
local function refresh_model(session, st)
  local snapshot = session.snapshot
  local wanted = session.tree_id
  if st.snapshot ~= snapshot or st.tree_id ~= wanted then
    st.snapshot, st.tree_id, st.tree, st.index, st.order = snapshot, wanted, nil, nil, {}
    for _, tree in ipairs(snapshot and snapshot.trees or {}) do
      if not st.tree or tree.id == wanted then st.tree = tree end
      if tree.id == wanted then break end
    end
    if st.tree then
      session.tree_id = st.tree.id; st.tree_id = st.tree.id
      st.collapsed_trees[st.tree_id] = st.collapsed_trees[st.tree_id] or {}
      st.collapsed = st.collapsed_trees[st.tree_id]
      st.index = Index.build(st.tree)
      st.order = Order.reading_order(st.tree, snapshot.rootDir)
      st.history[st.tree_id] = st.history[st.tree_id] or {}
    end
    st.revision = (st.revision or 0) + 1
  end
  local path = current_path(session)
  local relative = snapshot and C.relative(snapshot.rootDir, path) or path
  local current = st.index and Index.resolve_current(relative, { index = st.index, history = st.history[st.tree_id] })
  if st.current ~= current then
    st.current = current; st.revision = (st.revision or 0) + 1
    -- Expand ancestors only when the page changes. Manual collapse remains stable.
    if current then for _, node in ipairs(Index.breadcrumbs(st.index, current.id)) do st.collapsed[node.id] = nil end end
  end
  st.relative_path = relative
  st.previous, st.next = nil, nil
  for i, node in ipairs(st.order) do if current and current.id == node.id then st.previous, st.next = st.order[i - 1], st.order[i + 1]; break end end
end
local function source_row(session)
  if not valid(session.read_win) then return 0 end
  local cursor = vim.api.nvim_win_get_cursor(session.read_win)
  if session.map then return session.map:to_source(cursor[1] - 1, cursor[2]) end
  return cursor[1] - 1
end
local function heading_row(heading)
  return heading.range and heading.range.start.row or heading.start_row or heading.row or 0
end
local function heading_key(heading) return 'heading:' .. tostring(heading.id or heading_row(heading)) end
local function current_heading(session)
  local row, selected = source_row(session), nil
  for _, heading in ipairs(session.document and session.document.headings or {}) do
    if heading_row(heading) <= row then selected = heading else break end
  end
  return selected
end
local function write(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { '' })
  vim.bo[buf].modifiable = false
end
local function focus_reader(session)
  if valid(session.read_win) then vim.api.nvim_set_current_win(session.read_win) end
end
local function destroy(panel)
  if not panel then return end
  if valid(panel.win) then pcall(vim.api.nvim_win_close, panel.win, true) end
  if panel.buf and vim.api.nvim_buf_is_valid(panel.buf) then pcall(vim.api.nvim_buf_delete, panel.buf, { force = true }) end
end
local function options(win)
  for name, value in pairs({ number = false, relativenumber = false, wrap = false, cursorline = true, signcolumn = 'no', foldcolumn = '0', winfixwidth = true, spell = false, list = false }) do
    vim.api.nvim_set_option_value(name, value, { win = win })
  end
  vim.api.nvim_set_option_value('winhighlight', 'Normal:Normal,CursorLine:Visual', { win = win })
end
local function create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'; vim.bo[buf].bufhidden = 'wipe'; vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'md-readable-nav'
  return buf
end
local function panel_entry(panel)
  if not valid(panel.win) then return end
  return panel.entries and panel.entries[vim.api.nvim_win_get_cursor(panel.win)[1]]
end
local function rebuild(session, st, panel)
  local width = vim.api.nvim_win_get_width(panel.win)
  local key = table.concat({ tostring(st.revision), tostring(session.document), tostring(session.generation), tostring(width), panel.kind, tostring(session.stale), tostring(session.nav_result and session.nav_result.status) }, ':')
  if panel.cache_key == key then return end
  panel.cache_key = key
  local lines, entries = {}, {}
  local function add(text, entry)
    lines[#lines + 1] = clip(text, width)
    entries[#lines] = entry or { kind = 'label' }
  end
  add(panel.kind == 'outline' and 'On this page' or (st.tree and st.tree.title or 'Navigation'))
  add('Enter open  h/l fold  q back')
  if session.stale then add('[!] Stale navigation; r reload')
  elseif session.nav_result and session.nav_result.status == 'partial' then add('[!] Partial navigation; ? details') end
  local headings = session.document and session.document.headings or {}
  local function add_headings(depth, parent)
    local parents, hidden_level = {}, nil
    for heading_index, heading in ipairs(headings) do
      local level = heading.level or 1
      if hidden_level and level <= hidden_level then hidden_level = nil end
      if not hidden_level then
        local id = heading_key(heading)
        while #parents > 0 and parents[#parents].level >= level do table.remove(parents) end
        local next_heading = headings[heading_index + 1]
        local entry = { kind = 'heading', heading = heading, id = id, parent = parents[#parents] and parents[#parents].id or parent, expandable = next_heading and (next_heading.level or 1) > level or false }
        -- A following deeper heading makes this item expandable.
        local index = #lines + 1
        add(string.rep('  ', depth + math.max(0, level - 1)) .. '# ' .. heading.title, entry)
        if #parents > 0 then entries[parents[#parents].line].expandable = true end
        parents[#parents + 1] = { id = id, level = level, line = index }
        if st.collapsed[id] then hidden_level = level end
      end
    end
  end
  if panel.kind == 'outline' then add_headings(0)
  elseif st.tree then
    local function visit(nodes, depth, parent)
      for _, node in ipairs(nodes) do
        local current = st.current and st.current.id == node.id
        local with_headings = current and session.config.layout ~= 'separate' and #headings > 0
        local expandable = #node.children > 0 or with_headings
        local mark = expandable and (st.collapsed[node.id] and '+ ' or '- ') or '  '
        local target = node.target
        local suffix = target and target.type == 'unavailable' and ' [unavailable]' or target and target.type == 'external' and ' [web]' or ''
        add(string.rep('  ', depth) .. (current and '> ' or mark) .. node.title .. suffix, { kind = 'node', node = node, id = node.id, parent = parent, expandable = expandable })
        if not st.collapsed[node.id] then
          if with_headings then add_headings(depth + 1, node.id) end
          visit(node.children, depth + 1, node.id)
        end
      end
    end
    visit(st.tree.items, 0)
    if #st.tree.items == 0 then add('No entries in this tree.') end
  else
    if #headings > 0 then add_headings(0)
    elseif session.nav_result and session.nav_result.status == 'ambiguous' then add('Multiple projects. Press t to choose.')
    else add('No navigation. Press r to reload.') end
  end
  local old_entry = panel_entry(panel)
  local old_line = valid(panel.win) and vim.api.nvim_win_get_cursor(panel.win)[1] or 1
  write(panel.buf, lines); panel.entries = entries
  local selected_line
  if old_entry and old_entry.id then for i, entry in ipairs(entries) do if entry.id == old_entry.id then selected_line = i; break end end end
  vim.api.nvim_win_set_cursor(panel.win, { math.min(selected_line or old_line, #lines), 0 })
  vim.api.nvim_buf_clear_namespace(panel.buf, namespace, 0, -1)
  vim.api.nvim_buf_set_extmark(panel.buf, namespace, 0, 0, { end_row = 1, hl_group = 'Title', hl_eol = true })
  vim.api.nvim_buf_set_extmark(panel.buf, namespace, 1, 0, { end_row = 2, hl_group = 'Comment', hl_eol = true })
end
local function track(session, st, panel)
  local heading = current_heading(session)
  local id = heading and heading_key(heading)
  local chosen, page
  for i, entry in ipairs(panel.entries or {}) do
    if entry.id == id then chosen = i end
    if st.current and entry.id == st.current.id then page = i end
  end
  chosen = chosen or page
  if panel.current_mark then pcall(vim.api.nvim_buf_del_extmark, panel.buf, namespace, panel.current_mark); panel.current_mark = nil end
  if chosen then
    panel.current_mark = vim.api.nvim_buf_set_extmark(panel.buf, namespace, chosen - 1, 0, { end_row = chosen, hl_group = 'Search', hl_eol = true, priority = 100 })
    if vim.api.nvim_get_current_win() ~= panel.win then vim.api.nvim_win_set_cursor(panel.win, { chosen, 0 }) end
  end
end
local function activate(session, st, panel)
  local entry = panel_entry(panel)
  if not entry then return end
  if entry.kind == 'heading' then session:jump_source(heading_row(entry.heading), 0); focus_reader(session)
  elseif entry.kind == 'node' then
    local target = entry.node.target
    if target and target.type == 'document' then
      st.history[st.tree_id][target.path] = entry.id
      session:navigate(C.join(session.snapshot.rootDir, target.path), target.anchor)
      focus_reader(session)
    elseif target and target.type == 'external' then vim.ui.open(target.url)
    elseif target and target.type == 'unavailable' then vim.notify(target.reason, vim.log.levels.WARN)
    elseif entry.expandable then st.collapsed[entry.id] = not st.collapsed[entry.id]; st.revision = st.revision + 1; M.update(session) end
  end
  if panel.floating and entry.kind ~= 'label' and (entry.kind == 'heading' or (entry.node and entry.node.target and entry.node.target.type == 'document')) then
    destroy(panel); st.panels[panel.kind] = nil
  end
end
local function fold(session, st, panel, expand)
  local entry = panel_entry(panel); if not entry then return end
  if entry.expandable and (expand or not st.collapsed[entry.id]) then
    st.collapsed[entry.id] = not expand; st.revision = st.revision + 1; M.update(session)
  elseif not expand and entry.parent then
    for i, candidate in ipairs(panel.entries) do if candidate.id == entry.parent then vim.api.nvim_win_set_cursor(panel.win, { i, 0 }); break end end
  end
end
local function create_panel(session, st, kind, floating, focus)
  local buf, previous = create_buffer(), vim.api.nvim_get_current_win()
  local cfg = session.config.navigation or {}
  local width = cfg.width or 28
  local win
  if floating then
    width = math.max(1, math.min(vim.o.columns - 4, math.max(width, math.floor(vim.o.columns * 0.7))))
    local height = math.max(1, math.min(vim.o.lines - 5, math.floor(vim.o.lines * 0.75)))
    win = vim.api.nvim_open_win(buf, focus or false, { relative = 'editor', width = width, height = height, row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)), col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)), style = 'minimal', border = 'single', zindex = 60 })
  else
    vim.api.nvim_set_current_win(session.read_win)
    vim.cmd((kind == 'outline' and 'rightbelow' or 'leftabove') .. ' ' .. width .. 'vsplit')
    win = vim.api.nvim_get_current_win(); vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_width(win, width)
  end
  options(win)
  local panel = { buf = buf, win = win, kind = kind, floating = floating, entries = {} }
  st.panels[kind] = panel
  local function key(lhs, rhs, description) vim.keymap.set('n', lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = description }) end
  key('<CR>', function() activate(session, st, panel) end, 'Open selected document or heading')
  key('h', function() fold(session, st, panel, false) end, 'Collapse or select parent')
  key('l', function() fold(session, st, panel, true) end, 'Expand item')
  key('<Left>', function() fold(session, st, panel, false) end, 'Collapse or select parent')
  key('<Right>', function() fold(session, st, panel, true) end, 'Expand item')
  key('q', function() M.close(session); focus_reader(session) end, 'Close navigation and return to document')
  key('<Esc>', function() if floating then destroy(panel); st.panels[kind] = nil end; focus_reader(session) end, 'Return to document')
  key('<Tab>', function() focus_reader(session) end, 'Return to document')
  key('t', function() M.select(session) end, 'Choose tree or project')
  key('r', function() if session.load_navigation then session:load_navigation() end; M.update(session) end, 'Reload navigation')
  key('?', function()
    local details = { 'j/k or arrows: select; Enter: open; h/l: collapse/expand; q: close; Tab: return; t: tree/project; r: reload' }
    for _, d in ipairs(session.nav_result and session.nav_result.diagnostics or {}) do details[#details + 1] = d.message end
    vim.notify(table.concat(details, '\n'))
  end, 'Navigation help and diagnostics')
  if not focus and valid(previous) then vim.api.nvim_set_current_win(previous) end
  return panel
end
local function pager(session, st)
  if not valid(session.read_win) or not st.tree then destroy(st.pager); st.pager = nil; return end
  local width, height = vim.api.nvim_win_get_width(session.read_win), vim.api.nvim_win_get_height(session.read_win)
  if width < 20 or height < 4 then destroy(st.pager); st.pager = nil; return end
  local text = clip((session.stale and '[stale] ' or '') .. 'Prev: ' .. (st.previous and st.previous.title or '-') .. ' | Next: ' .. (st.next and st.next.title or '-'), width)
  if not st.pager or not valid(st.pager.win) then
    local buf = create_buffer()
    local win = vim.api.nvim_open_win(buf, false, { relative = 'win', win = session.read_win, row = height - 1, col = 0, width = width, height = 1, style = 'minimal', focusable = false, zindex = 40 })
    st.pager = { buf = buf, win = win }
    vim.api.nvim_set_option_value('winhighlight', 'Normal:StatusLine', { win = win })
  else
    vim.api.nvim_win_set_config(st.pager.win, { relative = 'win', win = session.read_win, row = height - 1, col = 0, width = width, height = 1 })
  end
  if st.pager.text ~= text then write(st.pager.buf, { text }); st.pager.text = text end
end
function M.update(session)
  local st = state(session)
  if st.updating or not st.open then return end
  if session.closed or not valid(session.read_win) then M.close(session); return end
  st.updating = true
  refresh_model(session, st)
  for kind, panel in pairs(st.panels) do
    if valid(panel.win) then rebuild(session, st, panel); track(session, st, panel)
    else st.panels[kind] = nil end
  end
  pager(session, st)
  st.updating = false
end
function M.open(session, opts)
  opts = opts or {}
  if session.closed or not valid(session.read_win) then return end
  if vim.o.columns < 24 or vim.o.lines < 8 then
    if opts.user then vim.notify('Navigation needs at least 24 columns and 8 rows', vim.log.levels.INFO) end
    return
  end
  local st = state(session); st.open = true
  refresh_model(session, st)
  local cfg, layout = session.config.navigation or {}, session.config.layout or 'integrated'
  local width, minimum = cfg.width or 28, cfg.min_body_width or 48
  local available = vim.api.nvim_win_get_width(session.read_win)
  for _, panel in pairs(st.panels) do if valid(panel.win) and not panel.floating then available = available + vim.api.nvim_win_get_width(panel.win) + 1 end end
  available = math.min(available, vim.o.columns)
  local narrow = available < minimum + width + 1
  st.available_width, st.lines = available, vim.o.lines
  if not st.panels.book and (opts.user or (not narrow and layout ~= 'ondemand')) then create_panel(session, st, 'book', narrow or layout == 'ondemand', opts.user) end
  if layout == 'separate' and not st.panels.outline and available >= minimum + width * 2 + 2 then create_panel(session, st, 'outline', false, false) end
  if not st.group then
    st.group = vim.api.nvim_create_augroup('MdReadableNavigation' .. st.id, { clear = true })
    vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, { group = st.group, callback = function()
      vim.schedule(function()
        if not st.open or session.closed or not valid(session.read_win) then return end
        local total = vim.api.nvim_win_get_width(session.read_win)
        for _, panel in pairs(st.panels) do if valid(panel.win) and not panel.floating then total = total + vim.api.nvim_win_get_width(panel.win) + 1 end end
        total = math.min(total, vim.o.columns)
        if total == st.available_width and st.lines == vim.o.lines then M.update(session); return end
        local active = vim.api.nvim_get_current_win()
        local was_focused = st.panels.book and st.panels.book.win == active
        local was_float = st.panels.book and st.panels.book.floating
        for kind, panel in pairs(st.panels) do destroy(panel); st.panels[kind] = nil end
        M.open(session, { user = was_focused or was_float })
      end)
    end })
  end
  M.update(session)
  return st.panels.book and st.panels.book.win
end
function M.close(session)
  local st = session._navigation; if not st then return end
  st.open = false
  for kind, panel in pairs(st.panels) do destroy(panel); st.panels[kind] = nil end
  destroy(st.pager); st.pager = nil
  if st.group then pcall(vim.api.nvim_del_augroup_by_id, st.group); st.group = nil end
end
function M.toggle(session)
  local st = state(session)
  if st.panels.book and valid(st.panels.book.win) then M.close(session); focus_reader(session)
  else local win = M.open(session, { user = true }); if valid(win) then vim.api.nvim_set_current_win(win) end end
end
function M.outline(session)
  local st = state(session); st.open = true; refresh_model(session, st)
  if st.panels.outline and valid(st.panels.outline.win) then vim.api.nvim_set_current_win(st.panels.outline.win)
  else create_panel(session, st, 'outline', true, true) end
  M.update(session)
end
function M.move(session, direction)
  local st = state(session); refresh_model(session, st)
  local node
  if direction == 'prev' or direction == 'previous' then node = st.previous else node = st.next end
  if not node then return false end
  st.history[st.tree_id][node.target.path] = node.id
  session:navigate(C.join(session.snapshot.rootDir, node.target.path), node.target.anchor)
  M.update(session)
  return true
end
function M.select(session)
  local result = session.nav_result
  if result and result.status == 'ambiguous' and result.candidates then
    vim.ui.select(result.candidates, { prompt = 'Navigation project', format_item = function(item) return item.adapter_id .. ' — ' .. item.root_dir .. ' (' .. table.concat(item.evidence or {}, ', ') .. ')' end }, function(choice)
      if not choice or session.closed then return end
      session.config.adapters = session.config.adapters or {}
      session.config.adapters.adapter, session.config.adapters.root_dir = choice.adapter_id, choice.root_dir
      session.config.adapters.config_path = choice.config_path
      session:load_navigation(); M.open(session, { user = true })
    end)
  else
    vim.ui.select(session.snapshot and session.snapshot.trees or {}, { prompt = 'Navigation tree', format_item = function(tree) return tree.title end }, function(tree)
      if not tree or session.closed then return end
      session.tree_id = tree.id; M.update(session); M.open(session, { user = true })
    end)
  end
end
return M
