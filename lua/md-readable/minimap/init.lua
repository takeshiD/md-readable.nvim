local M = {}
local render = require("md-readable.minimap.render")
---@type table<MdReadableSession, MdReadableMinimapState>
local states = setmetatable({}, { __mode = "k" })
local namespace = vim.api.nvim_create_namespace("MdReadableMinimap")

---@class MdReadableMinimapState
---@field regions? table<integer, string> 0-based minimap row to heading/code group
---@field win integer
---@field buf integer
---@field float boolean Placed beside a floating reading window
---@field original_width integer Reading window width before opening
---@field reserved_width? integer Reading float width while the minimap is open
---@field group? integer Autocommand group id
---@field rendered? MdReadableMinimapRendered
---@field signature? string
---@param session MdReadableSession
---@param state MdReadableMinimapState
---@return boolean?
local function valid(session, state)
  return state
    and not session.closed
    and vim.api.nvim_win_is_valid(session.read_win)
    and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_buf_is_valid(state.buf)
end

---@param session MdReadableSession
---@param state MdReadableMinimapState
local function current(session, state)
  if not valid(session, state) or not state.rendered then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  local cursor = vim.api.nvim_win_get_cursor(session.read_win)
  local row = state.rendered.display_to_mini[cursor[1]] or 0
  vim.api.nvim_buf_set_extmark(
    state.buf,
    namespace,
    row,
    0,
    { line_hl_group = "MdReadableMinimapCurrent", priority = 10 }
  )
  if vim.api.nvim_get_current_win() ~= state.win then
    vim.api.nvim_win_set_cursor(state.win, { row + 1, 0 })
  end
  for region_row, group in pairs(state.regions or {}) do
    vim.api.nvim_buf_set_extmark(state.buf, namespace, region_row, 0, {
      end_row = region_row + 1,
      end_col = 0,
      hl_group = group,
      priority = 15,
      strict = false,
    })
  end
end

-- Moves the reading view to the minimap cursor without leaving the minimap.
---@param session MdReadableSession
---@param state MdReadableMinimapState
local function follow(session, state)
  if not valid(session, state) or not state.rendered or vim.api.nvim_get_current_win() ~= state.win then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  local display = state.rendered.mini_to_display[row]
  local reader_row = vim.api.nvim_win_get_cursor(session.read_win)[1]
  -- Already inside this minimap row: keep the reader where it is.
  if not display or state.rendered.display_to_mini[reader_row] == row - 1 then
    return
  end
  vim.api.nvim_win_set_cursor(session.read_win, { display + 1, 0 })
  session:sync(session.read_win)
  require("md-readable.reader.focus").update(session)
  require("md-readable.ui.navigation").update(session)
  current(session, state)
end
---@param session MdReadableSession
---@return MdReadableMinimapState?
function M.get(session)
  return states[session]
end

---@param session MdReadableSession
function M.update(session)
  local state = states[session]
  if not state then
    return
  end
  if not valid(session, state) then
    M.close(session)
    return
  end
  local config = session.config.minimap or {}
  if state.float then
    vim.api.nvim_win_set_config(state.win, {
      relative = "win",
      win = session.read_win,
      row = 0,
      col = vim.api.nvim_win_get_width(session.read_win) + 1,
      height = math.max(1, vim.api.nvim_win_get_height(session.read_win)),
    })
  end
  local options = {
    width = math.max(1, vim.api.nvim_win_get_width(state.win)),
    height = vim.api.nvim_win_get_height(state.win),
    mode = config.mode,
    tabstop = vim.bo[session.read_buf].tabstop,
  }
  local signature = table.concat({
    tostring(session.rendered),
    session.generation or 0,
    session.source_buf,
    options.width,
    options.height,
    options.mode or "braille",
    options.tabstop,
  }, ":")
  if state.signature == signature then
    current(session, state)
    return
  end
  state.signature = signature
  state.rendered = render.render(session.rendered.lines, options)
  state.regions = render.regions(session.rendered, state.rendered)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, state.rendered.lines)
  vim.bo[state.buf].modifiable = false
  current(session, state)
end

---@param session MdReadableSession
---@return integer? win
---@return string? err
function M.open(session)
  if states[session] then
    return states[session].win
  end
  if session.closed or not vim.api.nvim_win_is_valid(session.read_win) then
    return nil, "reading window is closed"
  end
  local config = session.config.minimap or {}
  local available = vim.api.nvim_win_get_width(session.read_win)
  if available < 30 then
    return nil, "reading window needs at least 30 columns for the minimap"
  end
  local buf = vim.api.nvim_create_buf(false, true)
  -- Set before the window exists so window-layout plugins can identify it.
  vim.bo[buf].bufhidden, vim.bo[buf].filetype = "wipe", "md-readable-minimap"
  vim.bo[buf].swapfile, vim.bo[buf].modifiable = false, false
  local width = math.max(5, math.min(config.width or 12, math.floor(available / 3)))
  local reader_config = vim.api.nvim_win_get_config(session.read_win)
  local floating = reader_config.relative ~= ""
  local open_config = { split = "right", win = session.read_win, width = width }
  local reserved_width
  if floating then
    -- Keep the combined footprint within the original reading float. A nested
    -- split is illegal in Neovim, so reserve columns for an adjacent float.
    reserved_width = available - width - 2
    vim.api.nvim_win_set_config(session.read_win, { width = reserved_width })
    open_config = {
      relative = "win",
      win = session.read_win,
      row = 0,
      col = reserved_width + 1,
      width = width,
      height = vim.api.nvim_win_get_height(session.read_win),
      style = "minimal",
      border = "single",
    }
  end
  -- Without autocommands, layout plugins (e.g. windows.nvim autowidth) cannot
  -- resize the minimap before 'winfixwidth' is set below.
  open_config.noautocmd = true
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, open_config)
  if not ok then
    if floating then
      vim.api.nvim_win_set_config(session.read_win, { width = available })
    end
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil, win --[[@as string]]
  end
  local state = {
    win = win,
    buf = buf,
    float = floating,
    original_width = available,
    reserved_width = reserved_width,
  }
  states[session] = state
  for key, value in pairs({
    number = false,
    relativenumber = false,
    wrap = false,
    signcolumn = "no",
    foldcolumn = "0",
    cursorline = true,
    winfixwidth = true,
    winbar = "Minimap",
    statusline = " Enter: jump  q: close",
    statuscolumn = "", -- A split copies the reader's centering margin.
  }) do
    vim.wo[win][0][key] = value -- Local: a source shown here later gets plain options.
  end
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local display = state.rendered.mini_to_display[row] or 0
    local source, col = session.map:to_source(display, 0)
    session:jump_source(source, col)
    if vim.api.nvim_win_is_valid(session.read_win) then
      vim.api.nvim_set_current_win(session.read_win)
    end
  end, { buffer = buf, desc = "Jump to reading position" })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      M.close(session)
    end, { buffer = buf, desc = "Close minimap" })
  end
  state.group = vim.api.nvim_create_augroup("MdReadableMinimap" .. session.id, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.group,
    buffer = session.read_buf,
    callback = function()
      current(session, state)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = state.group,
    buffer = buf,
    callback = function()
      follow(session, state)
    end,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = state.group,
    callback = function()
      M.update(session)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.group,
    pattern = { tostring(win), tostring(session.read_win) },
    callback = function()
      -- Deferred: closing a window inside another window's close (for example
      -- :bdelete of the reading buffer) aborts that command with E855.
      vim.schedule(function()
        M.close(session)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.group,
    buffer = buf,
    callback = function()
      M.close(session)
    end,
  })
  M.update(session)
  -- The reading window lost columns; WinResized does not cover float resizes.
  session:schedule()
  return win
end

---@param session MdReadableSession
---@return integer? win
---@return string? err
function M.focus(session)
  local win, err = M.open(session)
  if win then
    vim.api.nvim_set_current_win(win)
  end
  return win, err
end

---@param session MdReadableSession
function M.close(session)
  local state = states[session]
  if not state then
    return
  end
  states[session] = nil
  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
  end
  if vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  -- The last window cannot close (:bdelete closed the reading window first):
  -- it becomes the source window instead of showing a stray buffer.
  if vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_buf_is_valid(session.source_buf) then
    vim.api.nvim_win_set_buf(state.win, session.source_buf)
    vim.wo[state.win].winfixwidth = false
  end
  if vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  if
    state.float
    and vim.api.nvim_win_is_valid(session.read_win)
    and vim.api.nvim_win_get_width(session.read_win) == state.reserved_width
  then
    pcall(vim.api.nvim_win_set_config, session.read_win, { width = state.original_width })
  end
  session:schedule()
end

---@param session MdReadableSession
---@return integer|false|nil win False when closed
---@return string? err
function M.toggle(session)
  if states[session] then
    M.close(session)
    return false
  end
  return M.open(session)
end

return M
