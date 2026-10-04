local M = {}
--- Show the full source text of the table cell under the cursor in a float.
---@param session MdReadableSession
function M.open(session)
  local pos = vim.api.nvim_win_get_cursor(session.read_win)
  local value
  for _, cell in ipairs(session.rendered.cells or {}) do
    if cell.row == pos[1] - 1 and pos[2] >= cell.start_col and pos[2] <= cell.end_col then
      value = cell.text
      break
    end
  end
  if not value then
    vim.notify("md-readable: no link or table cell at cursor")
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(value, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  local width = math.max(12, math.min(vim.o.columns - 4, 80))
  local height = math.max(1, math.min(vim.o.lines - 4, math.ceil(vim.fn.strdisplaywidth(value) / width) + #lines - 1))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = "single",
    style = "minimal",
    title = " Cell source ",
  })
  vim.wo[win].wrap = true
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
  end
end
return M
