-- User-facing failures are raised as tables so command handlers can show the
-- message alone, while unexpected Lua errors keep their location and traceback.
local M = {}
---@class MdReadableUserError
---@field message string
local UserError = {}
UserError.__index = UserError
UserError.__tostring = function(err)
  return err.message
end

---@param message any Raised as an MdReadableUserError; never returns
function M.user(message)
  error(setmetatable({ message = tostring(message) }, UserError), 0)
end

---@param err any
---@return boolean
function M.is_user(err)
  return getmetatable(err) == UserError
end

-- Runs fn and reports failures with vim.notify. User errors show only their
-- message; internal errors also record the traceback in :messages.
---@param fn function
---@param ... any Arguments for fn
---@return boolean ok
---@return any? err
function M.report(fn, ...)
  local args = vim.F.pack_len(...)
  local trace
  local ok, err = xpcall(function()
    return fn(vim.F.unpack_len(args))
  end, function(e)
    if not M.is_user(e) then
      trace = debug.traceback(tostring(e), 2)
    end
    return e
  end)
  if ok then
    return true
  end
  if trace then
    vim.api.nvim_echo({ { trace, "ErrorMsg" } }, true, {})
    vim.notify("md-readable: internal error: " .. tostring(err) .. " (see :messages)", vim.log.levels.ERROR)
  else
    vim.notify("md-readable: " .. tostring(err), vim.log.levels.ERROR)
  end
  return false, err
end

return M
