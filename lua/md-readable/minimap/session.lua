local M = {}
local states = setmetatable({}, { __mode = "k" })
function M.get(session)
  return states[session]
end
function M.set(session, state)
  states[session] = state
end
function M.remove(session)
  states[session] = nil
end
return M
