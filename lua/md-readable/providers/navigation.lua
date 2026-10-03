local M = { registered = {} }
function M.register(id, callback)
  assert(type(id) == 'string' and type(callback) == 'function', 'register(id, callback) requires a name and function')
  M.registered[id] = callback
  return function() if M.registered[id] == callback then M.registered[id] = nil end end
end
function M.load(provider, ctx)
  local result, ok
  if type(provider) == 'function' then ok, result = pcall(provider, ctx)
  elseif type(provider) == 'table' and provider.schemaVersion then ok, result = true, provider
  elseif type(provider) == 'table' and provider.path or type(provider) == 'string' and provider:match('%.json$') then
    local path = type(provider) == 'string' and provider or provider.path
    path = require('md-readable.adapters.common').join(ctx.root_dir, path)
    ok, result = pcall(function()
      local lines = ctx.read and ctx.read(path) or vim.fn.readfile(path)
      return vim.json.decode(type(lines) == 'table' and table.concat(lines, '\n') or lines)
    end)
  else
    local id = type(provider) == 'table' and provider.id or provider
    local callback = M.registered[id]
    if callback then ok, result = pcall(callback, ctx) else ok, result = false, 'Unregistered navigation provider: ' .. tostring(id) end
  end
  if not ok then return { status = 'error', diagnostics = { { severity = 'error', code = 'provider-error', message = tostring(result) } } } end
  local snapshot = type(result) == 'table' and (result.snapshot or result)
  local valid, diagnostics = require('md-readable.navigation.model').validate(snapshot)
  if not valid then return { status = 'error', diagnostics = diagnostics } end
  return { status = #snapshot.diagnostics > 0 and 'partial' or 'ok', snapshot = snapshot, diagnostics = snapshot.diagnostics, dependencies = result.dependencies or {} }
end
return M
