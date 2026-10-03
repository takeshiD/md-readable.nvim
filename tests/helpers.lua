local M = { count = 0, failed = 0 }
function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error((message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual), 2)
  end
end
function M.ok(value, message)
  if not value then error(message or "expected a truthy value", 2) end
end
function M.test(name, fn)
  M.count = M.count + 1
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then M.failed = M.failed + 1; print("FAIL " .. name .. "\n" .. err) end
end
function M.tempdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end
function M.write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
return M
