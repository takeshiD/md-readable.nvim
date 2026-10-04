local M = {}
local cache = require("md-readable.image.cache")

---@param url string
---@param opts? MdReadableConfigImages
---@param callback fun(path:string?,err:string?)
---@return fun() cancel
function M.fetch(url, opts, callback)
  opts = opts or {}
  if not opts.remote then
    callback(nil, "remote images are not allowed")
    return function() end
  end
  if not url:match("^https?://") then
    callback(nil, "only HTTP(S) image URLs are supported")
    return function() end
  end
  if vim.fn.executable("curl") ~= 1 then
    callback(nil, "curl is required to download remote images")
    return function() end
  end
  local extension = url:match("^[^?#]+"):match("%.([%a%d]+)$") or "image"
  local target, cache_err = cache.path("remote-v1:" .. url, "." .. extension, opts)
  if not target then
    callback(nil, cache_err)
    return function() end
  end
  local stat = vim.uv.fs_stat(target)
  if stat and os.time() - stat.mtime.sec < (opts.cache_ttl or 3600) then
    callback(target)
    return function() end
  end
  local temp, cancelled = cache.temporary(target), false
  local ok, process = pcall(vim.system, {
    "curl",
    "--fail",
    "--location",
    "--silent",
    "--show-error",
    "--proto",
    "=http,https",
    "--proto-redir",
    "=http,https",
    "--max-time",
    "30",
    "--max-filesize",
    tostring(opts.max_bytes or 20 * 1024 * 1024),
    "--output",
    temp,
    "--",
    url,
  }, { text = true, timeout = opts.timeout or 30000 }, function(result)
    vim.schedule(function()
      if cancelled then
        cache.remove(temp)
        return
      end
      local output = vim.uv.fs_stat(temp)
      if result.code ~= 0 or not output or output.size > (opts.max_bytes or 20 * 1024 * 1024) then
        cache.remove(temp)
        callback(nil, result.stderr ~= "" and result.stderr or "image download failed")
        return
      end
      local renamed, err = vim.uv.fs_rename(temp, target)
      if not renamed then
        cache.remove(temp)
        callback(nil, err)
        return
      end
      callback(target)
    end)
  end)
  if not ok then
    cache.remove(temp)
    callback(nil, process --[[@as string]])
  end
  return function()
    cancelled = true
    if ok and process then
      pcall(process.kill, process, 15)
    end
    cache.remove(temp)
  end
end

return M
