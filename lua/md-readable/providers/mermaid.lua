local M = {}
local cache = require('md-readable.image.cache')
local jobs = setmetatable({}, { __mode = 'k' })

function M.command(source, output, opts)
  opts = opts or {}
  local command = opts.command or 'mmdc'
  if type(command) ~= 'string' or vim.fs.basename(command) == 'npx' or vim.fs.basename(command) == 'npm' then
    return nil, 'Mermaid requires an installed renderer executable, not a package installer'
  end
  if vim.fn.executable(command) ~= 1 then return nil, 'install mmdc to render Mermaid diagrams' end
  return { command, '--input', source, '--output', output, '--outputFormat', 'png',
    '--theme', opts.theme or 'default', '--backgroundColor', opts.background or 'transparent',
    '--width', tostring(opts.width or 1600), '--height', tostring(opts.height or 1000) }
end

function M.render(session, descriptor, callback)
  local opts = session.config.mermaid or {}
  if opts.enabled == false then callback(nil, 'Mermaid rendering is disabled'); return function() end end
  local code = type(descriptor.code) == 'table' and table.concat(descriptor.code, '\n') or descriptor.code or ''
  local cache_opts = session.config.images or {}
  local key = table.concat({ 'mermaid-v1', code, opts.command or 'mmdc', opts.theme or 'default',
    opts.background or 'transparent', opts.width or 1600, opts.height or 1000 }, '\0')
  local target, cache_err = cache.path(key, '.png', cache_opts)
  if not target then callback(nil, cache_err); return function() end end
  if vim.uv.fs_stat(target) then callback(target); return function() end end
  local output = cache.temporary(target)
  local source = output .. '.mmd'
  local args, err = M.command(source, output, opts)
  if not args then callback(nil, err); return function() end end
  local written, write_err = pcall(vim.fn.writefile, vim.split(code, '\n', { plain = true }), source)
  if not written then callback(nil, write_err); return function() end end
  local cancelled, process = false, nil
  local entry = {}
  jobs[session] = jobs[session] or {}
  jobs[session][entry] = true
  local function cleanup()
    cache.remove(source); cache.remove(output)
    if jobs[session] then jobs[session][entry] = nil end
  end
  local ok, result = pcall(vim.system, args, { text = true, timeout = opts.timeout or 30000 }, function(done)
    vim.schedule(function()
      if cancelled or session.closed then cleanup(); return end
      if done.code ~= 0 then cleanup(); callback(nil, done.stderr ~= '' and done.stderr or 'Mermaid rendering failed'); return end
      local renamed, rename_err = vim.uv.fs_rename(output, target)
      cleanup()
      if renamed then callback(target) else callback(nil, rename_err) end
    end)
  end)
  if ok then process = result else cleanup(); callback(nil, result) end
  entry.cancel = function()
    cancelled = true
    if process then pcall(process.kill, process, 15) end
    cleanup()
  end
  return entry.cancel
end

function M.close(session)
  local pending = jobs[session]
  jobs[session] = nil
  for entry in pairs(pending or {}) do if entry.cancel then entry.cancel() end end
end

return M
