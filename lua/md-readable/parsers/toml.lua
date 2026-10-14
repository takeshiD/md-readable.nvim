local L = require("md-readable.parsers.literal")
local M = {}
---@param input string|string[]
---@param path? string For diagnostics
---@return table? value Ordered object; nil on error
---@return MdReadableParseDiagnostic[]
function M.parse(input, path)
  local text = type(input) == "table" and table.concat(input, "\n") or input --[[@as string]]
  local p = L.reader(text or "", "toml")
  local root, current = L.object(), nil
  current = root
  local ok, err = pcall(function()
    ---@return string[]
    local function keypath()
      local keys = { p:key() }
      while p:take(".") do
        keys[#keys + 1] = p:key()
      end
      return keys
    end
    ---@param keys string[]
    ---@param stop integer Number of keys to walk
    ---@return table
    local function container(keys, stop)
      local node = root
      for i = 1, stop do
        local k = keys[i]
        if node[k] == nil then
          L.put(node, k, L.object(), p:row())
        end
        node = node[k]
        if L.is_array(node) then
          node = node[#node]
        end
        if type(node) ~= "table" then
          error("table conflicts with scalar", 0)
        end
      end
      return node
    end
    while p:peek() ~= "" do
      if p:take("[") then
        local array = p:take("[")
        local keys = keypath()
        if not p:take("]") or (array and not p:take("]")) then
          error("unterminated table header", 0)
        end
        if array then
          local parent, key = container(keys, #keys - 1), keys[#keys]
          if parent[key] == nil then
            L.put(parent, key, {}, p:row())
          end
          if not L.is_array(parent[key]) then
            error("array table conflicts with existing table", 0)
          end
          current = L.object()
          table.insert(parent[key], current)
        else
          current = container(keys, #keys)
        end
      else
        local row, keys = p:row(), keypath()
        if not p:take("=") then
          error("expected =", 0)
        end
        local node = current
        for i = 1, #keys - 1 do
          if node[keys[i]] == nil then
            L.put(node, keys[i], L.object(), row)
          end
          node = node[keys[i]]
        end
        L.put(node, keys[#keys], p:value(), row)
      end
    end
  end)
  if not ok then
    return nil, { L.error(err, path, p:row()) }
  end
  return root, {}
end
M.keys = L.keys
return M
