vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./?.lua;./?/init.lua;" .. package.path
local t = require("tests.helpers")
for _, path in ipairs(vim.fn.glob("tests/test_*.lua", false, true)) do
  local ok, suite = pcall(dofile, path)
  if ok then
    local run, err = xpcall(function()
      suite(t)
    end, debug.traceback)
    if not run then
      t.failed = t.failed + 1
      print("FAIL suite " .. path .. "\n" .. err)
    end
  else
    t.failed = t.failed + 1
    print("FAIL load " .. path .. "\n" .. tostring(suite))
  end
end
print(string.format("md-readable: %d tests, %d failures", t.count, t.failed))
vim.cmd(t.failed == 0 and "qa!" or "cquit 1")
