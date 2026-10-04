local M = {}

---@param key string Hashed into the file name
---@param extension? string Defaults to ".png"
---@param opts? MdReadableConfigImages
---@return string? path
---@return string? err
function M.path(key, extension, opts)
  local dir = (opts or {}).cache_dir or vim.fn.stdpath("cache") .. "/md-readable/images"
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if not ok then
    return nil, err --[[@as string]]
  end
  if vim.fn.isdirectory(dir) ~= 1 then
    return nil, "could not create image cache directory: " .. dir
  end
  return dir .. "/" .. vim.fn.sha256(key) .. (extension or ".png")
end

---@param path string
---@return string? identity Path, size and mtime joined by ":"
---@return uv.fs_stat.result|string stat_or_err
function M.identity(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    return nil, "image file does not exist: " .. path
  end
  return table.concat({ path, stat.size, stat.mtime.sec, stat.mtime.nsec or 0 }, ":"), stat
end

---@param path string
---@return string
function M.temporary(path)
  return path .. "." .. tostring(vim.uv.hrtime()) .. ".tmp.png"
end

---@param path? string
function M.remove(path)
  if path then
    vim.uv.fs_unlink(path)
  end
end

---@param path string
---@param max_bytes? integer
---@param callback fun(data:string?,err:string?)
---@return fun() cancel
function M.read(path, max_bytes, callback)
  local cancelled = false
  vim.uv.fs_open(path, "r", 438, function(err, fd)
    if err then
      vim.schedule(function()
        if not cancelled then
          callback(nil, err)
        end
      end)
      return
    end
    vim.uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat or stat.size > (max_bytes or 20 * 1024 * 1024) then
        vim.uv.fs_close(fd)
        vim.schedule(function()
          if not cancelled then
            callback(nil, stat_err or "image exceeds max_bytes")
          end
        end)
        return
      end
      vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
        vim.uv.fs_close(fd)
        vim.schedule(function()
          if not cancelled then
            callback(data, read_err)
          end
        end)
      end)
    end)
  end)
  return function()
    cancelled = true
  end
end

return M
