local M = {}
local store = require('md-readable.minimap.session')
local render = require('md-readable.minimap.render')
local namespace = vim.api.nvim_create_namespace('MdReadableMinimap')
local symbols = { add = '+', change = '~', delete = '-' }
local diagnostic_symbols = { 'E', 'W', 'I', 'H' }
local diagnostic_groups = { 'DiagnosticError', 'DiagnosticWarn', 'DiagnosticInfo', 'DiagnosticHint' }

local function valid(session, state)
  return state and not session.closed and vim.api.nvim_win_is_valid(session.read_win)
    and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_buf_is_valid(state.buf)
end

local function current(session, state)
  if not valid(session, state) or not state.rendered then return end
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  local cursor = vim.api.nvim_win_get_cursor(session.read_win)
  local row = state.rendered.display_to_mini[cursor[1]] or 0
  vim.api.nvim_buf_set_extmark(state.buf, namespace, row, 0, { line_hl_group = 'MdReadableMinimapCurrent', priority = 10 })
  if vim.api.nvim_get_current_win() ~= state.win then
    vim.api.nvim_win_set_cursor(state.win, { row + 1, 2 })
  end
  for _, marker in ipairs(state.markers or {}) do
    vim.api.nvim_buf_set_extmark(state.buf, namespace, marker.row, marker.col, {
      end_col = marker.col + 1, hl_group = marker.group, priority = 20,
    })
  end
end

function M.update(session)
  local state = store.get(session)
  if not state then return end
  if not valid(session, state) then M.close(session); return end
  local config = session.config.minimap or {}
  if state.float then
    vim.api.nvim_win_set_config(state.win, { relative = 'win', win = session.read_win,
      row = 0, col = vim.api.nvim_win_get_width(session.read_win) + 1,
      height = math.max(1, vim.api.nvim_win_get_height(session.read_win)) })
  end
  if state.source_buf ~= session.source_buf then
    state.source_buf = session.source_buf
    state.providers.git, state.providers.diagnostic = {}, {}
    require('md-readable.minimap.git').close(session)
    require('md-readable.minimap.diagnostic').close(session)
    if config.git ~= false then require('md-readable.minimap.git').attach(session, M.set_annotations) end
    if config.diagnostic ~= false then require('md-readable.minimap.diagnostic').attach(session, M.set_annotations) end
  end
  local options = { width = math.max(1, vim.api.nvim_win_get_width(state.win) - 2),
    height = vim.api.nvim_win_get_height(state.win), mode = config.mode, tabstop = vim.bo[session.read_buf].tabstop }
  state.rendered = render.render(session.rendered.lines, options)
  local git = render.annotations(state.providers.git, session.map, state.rendered)
  local diagnostic = render.annotations(state.providers.diagnostic, session.map, state.rendered)
  local extra = {}
  for name, items in pairs(state.providers) do
    if name ~= 'git' and name ~= 'diagnostic' then
      for row, item in pairs(render.annotations(items, session.map, state.rendered)) do extra[row] = item end
    end
  end
  local lines, markers = {}, {}
  for index, line in ipairs(state.rendered.lines) do
    local row, g, d = index - 1, git[index - 1], diagnostic[index - 1]
    local gsym = g and symbols[g.kind] or (extra[row] and '*' or ' ')
    local dsym = d and diagnostic_symbols[d.severity or 1] or ' '
    lines[index] = (gsym or '*') .. (dsym or '?') .. line
    if g then markers[#markers + 1] = { row = row, col = 0, group = 'MdReadableGit' .. g.kind:gsub('^%l', string.upper) } end
    if d then markers[#markers + 1] = { row = row, col = 1, group = diagnostic_groups[d.severity or 1] or 'DiagnosticInfo' } end
  end
  state.markers = markers
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  current(session, state)
end

function M.set_annotations(session, provider_id, items)
  local state = store.get(session)
  if not state then return end
  state.providers[provider_id] = vim.deepcopy(items or {})
  M.update(session)
end

function M.open(session)
  if store.get(session) then return store.get(session).win end
  if session.closed or not vim.api.nvim_win_is_valid(session.read_win) then return nil, 'reading window is closed' end
  local config = session.config.minimap or {}
  local available = vim.api.nvim_win_get_width(session.read_win)
  if available < 30 then return nil, 'reading window needs at least 30 columns for the minimap' end
  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.max(5, math.min(config.width or 14, math.floor(available / 3)))
  local reader_config = vim.api.nvim_win_get_config(session.read_win)
  local floating = reader_config.relative ~= ''
  local open_config = { split = 'right', win = session.read_win, width = width }
  local reserved_width
  if floating then
    -- Keep the combined footprint within the original reading float. A nested
    -- split is illegal in Neovim, so reserve columns for an adjacent float.
    reserved_width = available - width - 2
    vim.api.nvim_win_set_config(session.read_win, { width = reserved_width })
    open_config = { relative = 'win', win = session.read_win, row = 0, col = reserved_width + 1,
      width = width, height = vim.api.nvim_win_get_height(session.read_win), style = 'minimal', border = 'single' }
  end
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, open_config)
  if not ok then
    if floating then vim.api.nvim_win_set_config(session.read_win, { width = available }) end
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil, win
  end
  local state = { win = win, buf = buf, providers = {}, source_buf = session.source_buf,
    float = floating, original_width = available, reserved_width = reserved_width }
  store.set(session, state)
  vim.bo[buf].bufhidden, vim.bo[buf].filetype = 'wipe', 'md-readable-minimap'
  vim.bo[buf].swapfile, vim.bo[buf].modifiable = false, false
  for key, value in pairs({ number = false, relativenumber = false, wrap = false, signcolumn = 'no',
    foldcolumn = '0', cursorline = true, winfixwidth = true, winbar = 'Minimap', statusline = ' Enter: jump  q: close' }) do vim.wo[win][key] = value end
  vim.keymap.set('n', '<CR>', function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local display = state.rendered.mini_to_display[row] or 0
    local source, col = session.map:to_source(display, 0)
    session:jump_source(source, col)
    if vim.api.nvim_win_is_valid(session.read_win) then vim.api.nvim_set_current_win(session.read_win) end
  end, { buffer = buf, desc = 'Jump to reading position' })
  for _, key in ipairs({ 'q', '<Esc>' }) do vim.keymap.set('n', key, function() M.close(session) end, { buffer = buf, desc = 'Close minimap' }) end
  state.group = vim.api.nvim_create_augroup('MdReadableMinimap' .. session.id, { clear = true })
  vim.api.nvim_create_autocmd('CursorMoved', { group = state.group, buffer = session.read_buf,
    callback = function() current(session, state) end })
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, { group = state.group,
    callback = function() M.update(session) end })
  vim.api.nvim_create_autocmd('WinClosed', { group = state.group, pattern = { tostring(win), tostring(session.read_win) },
    callback = function() M.close(session) end })
  vim.api.nvim_create_autocmd('BufWipeout', { group = state.group, buffer = buf, callback = function() M.close(session) end })
  M.update(session)
  if config.git ~= false then require('md-readable.minimap.git').attach(session, M.set_annotations) end
  if config.diagnostic ~= false then require('md-readable.minimap.diagnostic').attach(session, M.set_annotations) end
  return win
end

function M.focus(session)
  local win, err = M.open(session)
  if win then vim.api.nvim_set_current_win(win) end
  return win, err
end

function M.close(session)
  local state = store.get(session)
  if not state then return end
  store.remove(session)
  require('md-readable.minimap.git').close(session)
  require('md-readable.minimap.diagnostic').close(session)
  if state.group then pcall(vim.api.nvim_del_augroup_by_id, state.group) end
  if vim.api.nvim_win_is_valid(state.win) then pcall(vim.api.nvim_win_close, state.win, true) end
  if vim.api.nvim_buf_is_valid(state.buf) then pcall(vim.api.nvim_buf_delete, state.buf, { force = true }) end
  if state.float and vim.api.nvim_win_is_valid(session.read_win)
    and vim.api.nvim_win_get_width(session.read_win) == state.reserved_width then
    pcall(vim.api.nvim_win_set_config, session.read_win, { width = state.original_width })
  end
end

function M.toggle(session)
  if store.get(session) then M.close(session); return false end
  return M.open(session)
end

return M
