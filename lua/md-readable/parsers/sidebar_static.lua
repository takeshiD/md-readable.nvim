-- Reads literal JS/TS data only. Identifiers refer solely to already parsed
-- literal declarations; project imports, functions and expressions never run.
local L = require("md-readable.parsers.literal")
local M = {}
-- Parses a literal or a module whose default export is a literal binding.
---@param input string|string[]
---@param path? string For diagnostics
---@return any value nil on error
---@return MdReadableParseDiagnostic[]
function M.parse(input, path)
  local text = type(input) == "table" and table.concat(input, "\n") or input --[[@as string]]
  local p, bindings = L.reader(text, "js"), {}
  local ok, result = pcall(function()
    if p:peek() == "{" or p:peek() == "[" then
      local v = p:value()
      p:take(";")
      p:skip()
      if p.pos <= #text then
        error("unexpected trailing expression", 0)
      end
      return v
    end
    local output
    while p:peek() ~= "" do
      if p:take("import") then
        -- Imports are declarations only and intentionally never resolved.
        while p:peek() ~= "" and not p:take(";") do
          if p:peek() == '"' or p:peek() == "'" then
            p:string()
            p:take(";")
            break
          else
            p.pos = p.pos + 1
          end
        end
      elseif p:take("const") or p:take("let") then
        local key = p:key()
        if p:take(":") then
          local annotation = text:sub(p.pos):match("^%s*[%w_.$]+%s*")
          if not annotation then
            error("unsupported TypeScript annotation", 0)
          end
          p.pos = p.pos + #annotation
        end
        if not p:take("=") then
          error("expected literal declaration", 0)
        end
        bindings[key] = p:value()
        if p:take("as") then
          if not p:take("const") then
            error("only as const is supported", 0)
          end
        end
        if p:take("satisfies") then
          p:key()
        end
        p:take(";")
      elseif p:take("module.exports") or p:take("export default") then
        p:take("=")
        if p:peek() == "{" or p:peek() == "[" then
          output = p:value()
        else
          local key = p:key()
          output = bindings[key]
          if output == nil then
            error("export is not a static binding: " .. key, 0)
          end
        end
        if p:take("as") then
          if not p:take("const") then
            error("only as const is supported", 0)
          end
        end
        if p:take("satisfies") then
          p:key()
        end
        p:take(";")
      else
        error("unsupported JavaScript/TypeScript expression; use a literal sidebar or navigation provider", 0)
      end
    end
    if output == nil then
      error("no static default/module.exports export", 0)
    end
    return output
  end)
  if not ok then
    return nil, { L.error(result, path, p:row()) }
  end
  return result, {}
end
-- Lexically locate a property or call without matching comments/string contents.
-- This supports literal sidebar options inside normal framework config wrappers.
---@param input string|string[]
---@param name string Property or function name
---@param kind "property"|"call" `name: value` or `name(value)`
---@param path? string For diagnostics
---@return any value nil when absent or on error
---@return MdReadableParseDiagnostic[]
function M.extract(input, name, kind, path)
  local text = type(input) == "table" and table.concat(input, "\n") or input --[[@as string]]
  local p = L.reader(text, "js")
  local ok, value = pcall(function()
    while p:peek() ~= "" do
      local c = p:peek()
      if c == '"' or c == "'" then
        local key = p:string()
        if kind ~= "call" and key == name and p:take(":") then
          return p:value()
        end
      elseif c:match("[%a_$]") then
        local key = p:key()
        if key == name and p:take(kind == "call" and "(" or ":") then
          return p:value()
        end
      elseif c == "`" then
        error("template literals in config require an explicit provider", 0)
      else
        p.pos = p.pos + 1
      end
    end
  end)
  if not ok then
    return nil, { L.error(value, path, p:row()) }
  end
  return value, {}
end
return M
