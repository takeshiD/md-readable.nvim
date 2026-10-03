local M = {}
local states = setmetatable({}, { __mode = "k" })

function M.collect(buf, severity)
  local items = {}
  if not vim.api.nvim_buf_is_valid(buf) then
    return items
  end
  local options = severity and { severity = severity } or {}
  for _, diagnostic in ipairs(vim.diagnostic.get(buf, options)) do
    items[#items + 1] = {
      start_row = diagnostic.lnum,
      end_row = math.max(diagnostic.lnum + 1, (diagnostic.end_lnum or diagnostic.lnum) + 1),
      kind = "diagnostic",
      severity = diagnostic.severity or vim.diagnostic.severity.ERROR,
    }
  end
  return items
end

function M.update(session)
  local state = states[session]
  if not state or session.closed then
    return
  end
  local config = session.config.minimap or {}
  state.publish(session, "diagnostic", M.collect(session.source_buf, config.severity))
end

function M.attach(session, publish)
  M.close(session)
  local state =
    { publish = publish, group = vim.api.nvim_create_augroup("MdReadableDiagnostics" .. session.id, { clear = true }) }
  states[session] = state
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = state.group,
    buffer = session.source_buf,
    callback = function()
      M.update(session)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.group,
    buffer = session.source_buf,
    callback = function()
      publish(session, "diagnostic", {})
      M.close(session)
    end,
  })
  M.update(session)
end

function M.close(session)
  local state = states[session]
  if not state then
    return
  end
  states[session] = nil
  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
  end
end

return M
