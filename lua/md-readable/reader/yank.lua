local M = {}
-- Byte just after the UTF-8 character starting at col.
---@param line string
---@param col integer 0-based byte column
---@return integer
local function char_end(line, col)
  if col >= #line then
    return #line
  end
  local byte = line:byte(col + 1)
  return math.min(#line, col + (byte < 128 and 1 or byte < 224 and 2 or byte < 240 and 3 or 4))
end
---@param session MdReadableSession
function M.capture(session)
  local reg = vim.v.register
  session.yank_previous = {}
  for _, name in ipairs({ '"', "0", reg:lower() }) do
    session.yank_previous[name] = vim.fn.getreginfo(name)
  end
  session.yank_register = reg
end
---@param session MdReadableSession
local function restore(session)
  for name, value in pairs(session.yank_previous or {}) do
    pcall(vim.fn.setreg, name, value)
  end
end
---@param session MdReadableSession
---@param event table vim.v.event of TextYankPost
function M.handle(session, event)
  if event.operator ~= "y" or not session.map then
    return
  end
  if vim.api.nvim_buf_get_changedtick(session.source_buf) ~= session.document.changedtick then
    restore(session)
    vim.notify("md-readable: source changed; refresh before copying", vim.log.levels.WARN)
    return
  end
  local start = vim.api.nvim_buf_get_mark(session.read_buf, "[")
  local finish = vim.api.nvim_buf_get_mark(session.read_buf, "]")
  local sr, sc, er, ec = start[1] - 1, start[2], finish[1] - 1, finish[2]
  local mode = event.regtype == "V" and "line" or event.regtype:sub(1, 1) == "\22" and "block" or "char"
  if mode == "line" then
    er, ec = er + 1, 0
  elseif event.inclusive then
    ec = char_end(session.rendered.lines[er + 1] or "", ec)
  end
  local columns
  if mode == "block" then
    columns = {}
    local left = vim.fn.virtcol({ sr + 1, sc + 1 }, true)[1]
    local width = tonumber(event.regtype:sub(2)) or 1
    for row = sr, er do
      local line = session.rendered.lines[row + 1] or ""
      local first = vim.fn.virtcol2col(session.read_win, row + 1, left)
      local last = vim.fn.virtcol2col(session.read_win, row + 1, left + width - 1)
      columns[row] = { first > 0 and first - 1 or #line, last > 0 and char_end(line, last - 1) or #line }
    end
  end
  local text, kind = session.map:copy(sr, sc, er, ec, mode, columns)
  if text == nil then
    restore(session)
    vim.notify("md-readable: selection contains no source text")
    return
  end
  local reg = session.yank_register or event.regname
  if reg == "" then
    reg = '"'
  end
  if reg == "_" then
    session.yank_previous, session.yank_register = nil, nil
    return
  end
  if reg:match("^[A-Z]$") then
    local previous = session.yank_previous and session.yank_previous[reg:lower()]
    if previous then
      vim.fn.setreg(reg:lower(), previous)
    end
  end
  vim.fn.setreg(reg, text, kind)
  if reg:match("^[A-Z]$") then
    vim.fn.setreg('"', vim.fn.getreginfo(reg:lower()))
  else
    vim.fn.setreg('"', text, kind)
  end
  if reg == '"' then
    vim.fn.setreg("0", text, kind)
  end
  session.yank_previous, session.yank_register = nil, nil
end
---@param session MdReadableSession
function M.attach(session)
  for _, mode in ipairs({ "n", "x" }) do
    vim.keymap.set(mode, "y", function()
      M.capture(session)
      return "y"
    end, { buffer = session.read_buf, expr = true, desc = "Copy Markdown source" })
  end
  vim.keymap.set("n", "Y", function()
    M.capture(session)
    return "y$"
  end, { buffer = session.read_buf, expr = true, desc = "Copy Markdown source to end of line" })
end
return M
