local M = {}
local cache = require("md-readable.image.cache")

---@param path string
---@param output string
---@param opts? MdReadableConfigImages
---@return string[]? args
---@return string? err
function M.command(path, output, opts)
  opts = opts or {}
  local extension = path:lower():match("%.([%w]+)$")
  local tool = opts.converter
  if not tool then
    for _, candidate in
      ipairs(
        extension == "svg" and { "rsvg-convert", "magick", "convert", "ffmpeg" } or { "magick", "convert", "ffmpeg" }
      )
    do
      if vim.fn.executable(candidate) == 1 then
        tool = candidate
        break
      end
    end
  end
  if not tool or vim.fn.executable(tool) ~= 1 then
    return nil, "install ImageMagick or an image converter to display this format"
  end
  local name = vim.fs.basename(tool)
  if name == "rsvg-convert" then
    return { tool, "--keep-aspect-ratio", "--width", "2048", "--output", output, path }
  end
  if name == "ffmpeg" then
    return {
      tool,
      "-nostdin",
      "-v",
      "error",
      "-y",
      "-i",
      path,
      "-frames:v",
      "1",
      "-vf",
      "scale='min(2048,iw)':-1",
      output,
    }
  end
  return { tool, path .. "[0]", "-resize", "2048x2048>", "PNG:" .. output }
end

-- Calls back with a PNG path: the original file, or a cached conversion.
---@param path string
---@param opts? MdReadableConfigImages
---@param callback fun(png:string?,err:string?)
---@return fun() cancel
function M.ensure(path, opts, callback)
  opts = opts or {}
  local identity, stat = cache.identity(path)
  if not identity then
    callback(nil, stat --[[@as string]])
    return function() end
  end
  if stat.size > (opts.max_bytes or 20 * 1024 * 1024) then
    callback(nil, "image exceeds max_bytes")
    return function() end
  end
  local cancelled, process, output = false, nil, nil
  ---@param result? string
  ---@param err? string
  local function finish(result, err)
    if not cancelled then
      callback(result, err)
    end
  end
  local cancel_read = cache.read(path, opts.max_bytes, function(data, err)
    if not data then
      finish(nil, err)
      return
    end
    if data:sub(1, 8) == "\137PNG\13\10\26\10" then
      finish(path)
      return
    end
    local target, cache_err = cache.path("convert-v1:" .. identity .. ":" .. tostring(opts.converter), ".png", opts)
    if not target then
      finish(nil, cache_err)
      return
    end
    if vim.uv.fs_stat(target) then
      finish(target)
      return
    end
    output = cache.temporary(target)
    local args, command_err = M.command(path, output, opts)
    if not args then
      finish(nil, command_err)
      return
    end
    local ok, result = pcall(vim.system, args, { text = true, timeout = opts.timeout or 30000 }, function(done)
      vim.schedule(function()
        if cancelled then
          cache.remove(output)
          return
        end
        if done.code ~= 0 then
          cache.remove(output)
          finish(nil, done.stderr ~= "" and done.stderr or "image conversion failed")
          return
        end
        local renamed, rename_err = vim.uv.fs_rename(output, target)
        if not renamed then
          cache.remove(output)
          finish(nil, rename_err)
          return
        end
        finish(target)
      end)
    end)
    if ok then
      process = result
    else
      finish(nil, result --[[@as string]])
    end
  end)
  return function()
    cancelled = true
    cancel_read()
    if process then
      pcall(process.kill, process, 15)
    end
    cache.remove(output)
  end
end

return M
