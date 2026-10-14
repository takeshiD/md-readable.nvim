-- Mermaid as text with termaid (mermaid.renderer = "termaid"): the diagram is
-- Unicode box drawing, so it needs no image support from the terminal. Output
-- is cached per diagram, width and arguments; a render runs termaid only for
-- diagrams it has not seen.
local M = {}
---@type table<string, string[]|false> Cache key to lines, false for a failure
local cache = {}
---@type string[] Cache keys, oldest first
local order = {}
local limit = 200
---@type table<string, string> Cache key to the reason of a failure
M.errors = {}

---@param key string
---@param value string[]|false
local function remember(key, value)
  if cache[key] == nil then
    order[#order + 1] = key
    if #order > limit then
      local oldest = table.remove(order, 1)
      cache[oldest], M.errors[oldest] = nil, nil
    end
  end
  cache[key] = value
end

-- termaid_opts keys and their flags; a number value follows its flag.
local flags = {
  ascii = "--ascii",
  sharp_edges = "--sharp-edges",
  inline_edge_labels = "--inline-edge-labels",
  gap = "--gap",
  padding_x = "--padding-x",
  padding_y = "--padding-y",
}
M.flags = flags

-- Command line for a diagram `width` cells wide: mermaid.command/args, the
-- termaid_opts flags, then --width.
---@param width integer
---@param opts? MdReadableConfigMermaid
---@return string[]? argv
---@return string? err
function M.command(width, opts)
  local argv, err = require("md-readable.providers.mermaid").base(
    vim.tbl_extend("force", opts or {}, { renderer = "termaid" }) --[[@as MdReadableConfigMermaid]]
  )
  if not argv then
    return nil, err
  end
  local termaid_opts = (opts or {}).termaid_opts or {}
  local names = vim.tbl_keys(termaid_opts)
  table.sort(names)
  for _, name in ipairs(names) do
    local value = termaid_opts[name]
    if value == true then
      argv[#argv + 1] = flags[name]
    elseif type(value) == "number" then
      vim.list_extend(argv, { flags[name], tostring(value) })
    end
  end
  vim.list_extend(argv, { "--width", tostring(math.max(1, width)) })
  return argv
end

-- Lines of the diagram, or nil and the reason when it cannot be drawn.
---@param code string Mermaid source
---@param width integer Cells available
---@param opts? MdReadableConfigMermaid
---@return string[]? lines
---@return string? err
function M.render(code, width, opts)
  local args, command_err = M.command(width, opts)
  if not args then
    return nil, command_err
  end
  local key = table.concat(args, "\0") .. "\0" .. code
  if cache[key] ~= nil then
    return cache[key] or nil, M.errors[key]
  end
  local ok, result = pcall(function()
    return vim.system(args, { stdin = code, text = true, timeout = (opts or {}).timeout or 5000 }):wait()
  end)
  local lines = false ---@type string[]|false
  local err ---@type string?
  if not ok then
    err = tostring(result)
  elseif result.code ~= 0 or vim.trim(result.stdout or "") == "" then
    err = vim.trim((result.stderr or "") ~= "" and result.stderr or "termaid produced no output")
  else
    lines = vim.split((result.stdout:gsub("%s+$", "")), "\n", { plain = true })
  end
  remember(key, lines)
  M.errors[key] = err
  return lines or nil, err
end

return M
