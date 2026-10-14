-- Paragraph search semantics adapted from limelight.vim:
-- Copyright (c) 2015 Junegunn Choi. MIT License.
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
local M = {}
---@class MdReadableFocusRange
---@field start_row integer 0-based display row
---@field end_row integer Exclusive
---@class MdReadableFocusState
---@field win integer
---@field range? MdReadableFocusRange Fixed range; nil follows the cursor paragraph
---@field matches integer[] matchadd() ids
---@field group? integer Autocommand group
---@type table<MdReadableSession, MdReadableFocusState>
local states = setmetatable({}, { __mode = "k" })

---@param state MdReadableFocusState
local function clear(state)
  if vim.api.nvim_win_is_valid(state.win) then
    for _, id in ipairs(state.matches or {}) do
      pcall(vim.fn.matchdelete, id, state.win)
    end
  end
  state.matches = {}
end

-- Returns inclusive one-based boundaries, as Limelight does. Zero means the
-- search reached the file boundary. Search restores both cursor and viewport.
---@param win integer
---@param opts? MdReadableConfigFocus|MdReadableUserConfigFocus
---@return integer[] bounds {first, last}
function M.bounds(win, opts)
  opts = opts or {}
  return vim.api.nvim_win_call(win, function()
    local view, position = vim.fn.winsaveview(), vim.fn.getcurpos()
    local span = math.max(0, (opts.span or 0) - (vim.fn.getline("."):match("^%s*$") and 1 or 0))
    local first, last = 0, 0
    local ok, err = pcall(function()
      for i = 0, span do
        first = vim.fn.searchpos(opts.bop or "^\\s*$\\n\\zs", i == 0 and "cbW" or "bW")[1]
      end
      vim.fn.setpos(".", position)
      for _ = 0, span do
        last = vim.fn.searchpos(opts.eop or "^\\s*$", "W")[1]
      end
    end)
    vim.fn.winrestview(view)
    if not ok then
      error(err)
    end
    return { first, last }
  end)
end

---@param win integer
---@param opts MdReadableConfigFocus|MdReadableUserConfigFocus
---@return string color "#rrggbb"
local function color(win, opts)
  if opts.color then
    return opts.color
  end
  local ns = vim.api.nvim_get_hl_ns and vim.api.nvim_get_hl_ns({ winid = win }) or 0
  local normal = vim.api.nvim_get_hl(math.max(ns, 0), { name = "Normal", link = false })
  local fallback = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local light = vim.o.background == "light"
  local fg, bg =
    normal.fg or fallback.fg or (light and 0x303030 or 0xd0d0d0),
    normal.bg or fallback.bg or (light and 0xffffff or 0x101010)
  local coefficient = math.max(0, math.min(1, opts.coefficient or 0.5))
  local result = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local f, b = bit.band(bit.rshift(fg, shift), 255), bit.band(bit.rshift(bg, shift), 255)
    result = result + math.floor(f * (1 - coefficient) + b * coefficient) * 2 ^ shift
  end
  return string.format("#%06x", result)
end

---@param session MdReadableSession
function M.update(session)
  local state = states[session]
  if not state then
    return
  end
  if session.closed or not vim.api.nvim_win_is_valid(session.read_win) then
    M.close(session)
    return
  end
  if state.win ~= session.read_win then
    clear(state)
    state.win = session.read_win
  end
  local opts = (session.config or {}).focus or {}
  local bounds = state.range and { state.range.start_row + 1, state.range.end_row } or M.bounds(state.win, opts)
  clear(state)
  local group = "MdReadableFocusDim" .. state.win
  vim.api.nvim_set_hl(0, group, { fg = color(state.win, opts), ctermfg = opts.cterm_color or 8 })
  vim.api.nvim_win_call(state.win, function()
    state.matches[#state.matches + 1] = vim.fn.matchadd(group, "\\%<" .. bounds[1] .. "l", opts.priority or 10)
    if bounds[2] > 0 then
      state.matches[#state.matches + 1] = vim.fn.matchadd(group, "\\%>" .. bounds[2] .. "l", opts.priority or 10)
    end
  end)
end

---@param session MdReadableSession
---@param enabled? boolean nil toggles
---@param range? MdReadableFocusRange
---@return boolean enabled
function M.set(session, enabled, range)
  if enabled == nil then
    enabled = states[session] == nil
  end
  if not enabled then
    M.close(session)
    return false
  end
  M.close(session)
  local state = { win = session.read_win, range = range and vim.deepcopy(range), matches = {} }
  states[session] = state
  state.group = vim.api.nvim_create_augroup("MdReadableFocus" .. session.id, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged" }, {
    group = state.group,
    buffer = session.read_buf,
    callback = function()
      M.update(session)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = state.group,
    callback = function()
      vim.schedule(function()
        M.update(session)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = state.group,
    pattern = "MdReadableThemeChanged",
    callback = function()
      M.update(session)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.group,
    pattern = tostring(state.win),
    callback = function()
      M.close(session)
    end,
  })
  M.update(session)
  return true
end

---@param session MdReadableSession
function M.close(session)
  local state = states[session]
  if not state then
    return
  end
  states[session] = nil
  clear(state)
  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
  end
end

return M
