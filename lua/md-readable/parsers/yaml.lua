-- Deliberately scoped YAML data parser: block maps/sequences and flow literals.
-- Ordered maps retain keys/source rows in a metatable, without polluting values.
local L = require('md-readable.parsers.literal')
local M = {}
local function strip_comment(s)
  local quote, escape
  for i = 1, #s do
    local c = s:sub(i, i)
    if escape then escape = false
    elseif c == '\\' and quote == '"' then escape = true
    elseif quote then if c == quote then quote = nil end
    elseif c == '"' or c == "'" then quote = c
    elseif c == '#' and (i == 1 or s:sub(i - 1, i - 1):match('%s')) then return s:sub(1, i - 1) end
  end
  return s
end
local function pair(s)
  local quote, depth, escape = nil, 0, false
  for i = 1, #s do
    local c = s:sub(i, i)
    if escape then escape = false
    elseif quote and c == '\\' then escape = true
    elseif quote then if c == quote then quote = nil end
    elseif c == '"' or c == "'" then quote = c
    elseif c == '[' or c == '{' then depth = depth + 1
    elseif c == ']' or c == '}' then depth = depth - 1
    elseif c == ':' and depth == 0 and (i == #s or s:sub(i + 1, i + 1):match('%s')) then
      return vim.trim(s:sub(1, i - 1)), vim.trim(s:sub(i + 1))
    end
  end
end
function M.parse(input, path)
  local lines = type(input) == 'string' and vim.split(input, '\n', { plain = true }) or input
  local tokens, row = {}, 0
  local ok, value = pcall(function()
    for i, line in ipairs(lines or {}) do
      row = i - 1
      if line:match('^%s*\t') then error('tabs in YAML indentation are unsupported', 0) end
      local indent, text = line:match('^( *)(.*)$')
      text = vim.trim(strip_comment(text))
      if text == '---' and #tokens > 0 then error('multiple YAML documents are unsupported', 0) end
      if text ~= '' and text ~= '---' and text ~= '...' then
        tokens[#tokens + 1] = { indent = #indent, text = text, row = row, raw = line }
      end
    end
    local pos = 1
    local parse_block
    local function scalar(s)
      if s:match('^[!&*]') or s:match('^<<') then error('YAML tags, anchors, aliases and merges require an explicit provider', 0) end
      if s:sub(1, 1) == '[' or s:sub(1, 1) == '{' or s:sub(1, 1) == '"' or s:sub(1, 1) == "'" then
        local v, errors = L.parse(s, 'yaml', path)
        if not v then error(errors[1].message, 0) end
        return v
      end
      if s == 'true' then return true end
      if s == 'false' then return false end
      if s == 'null' or s == '~' then return vim.NIL end
      return tonumber(s) or s
    end
    local function parse_value(s, indent)
      if s == '' then
        if tokens[pos] and tokens[pos].indent > indent then return parse_block(tokens[pos].indent) end
        -- YAML allows an indentless block sequence beneath a mapping key.
        if tokens[pos] and tokens[pos].indent == indent and tokens[pos].text:match('^%-%s') then return parse_block(indent) end
        return vim.NIL
      end
      if s:match('^[|>][%+%-]?$') then
        local parts = {}
        local base = tokens[pos] and tokens[pos].indent
        while tokens[pos] and tokens[pos].indent > indent do
          parts[#parts + 1] = tokens[pos].raw:sub(base + 1); pos = pos + 1
        end
        return table.concat(parts, s:sub(1, 1) == '>' and ' ' or '\n') .. (s:sub(-1) == '-' and '' or '\n')
      end
      return scalar(s)
    end
    local function add_pair(out, s, indent, source_row)
      local key, val = pair(s)
      if not key then error('expected YAML key: value', 0) end
      if key == '<<' then error('YAML merge keys are unsupported', 0) end
      if key:sub(1, 1) == '"' or key:sub(1, 1) == "'" then key = scalar(key) end
      L.put(out, key, parse_value(val, indent), source_row)
    end
    parse_block = function(indent)
      local sequence = tokens[pos].text:match('^%-%s') or tokens[pos].text == '-'
      local out = sequence and {} or L.object()
      while tokens[pos] and tokens[pos].indent == indent do
        local token = tokens[pos]; row = token.row; pos = pos + 1
        if sequence then
          local rest = token.text:match('^%-%s+(.*)$') or (token.text == '-' and '')
          if not rest then error('mixed sequence and mapping', 0) end
          if pair(rest) then
            local obj = L.object()
            add_pair(obj, rest, indent + 2, token.row)
            while tokens[pos] and tokens[pos].indent > indent do
              local continuation = tokens[pos]
              if continuation.indent ~= indent + 2 then error('unexpected mapping indentation', 0) end
              pos = pos + 1; row = continuation.row
              add_pair(obj, continuation.text, continuation.indent, continuation.row)
            end
            out[#out + 1] = obj
          else out[#out + 1] = parse_value(rest, indent) end
        else
          add_pair(out, token.text, indent, token.row)
        end
      end
      return out
    end
    if #tokens == 0 then return L.object() end
    local out = parse_block(tokens[1].indent)
    if pos <= #tokens then row = tokens[pos].row; error('unexpected YAML indentation', 0) end
    return out
  end)
  if not ok then return nil, { L.error(value, path, row) } end
  return value, {}
end
M.keys = L.keys
return M
