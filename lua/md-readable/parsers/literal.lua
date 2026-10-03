-- Static data reader. No load(), shell, JavaScript runtime, or project code execution.
local M = {}
function M.object()
  return setmetatable({}, { __keys = {}, __positions = {} })
end
function M.put(t, key, value, row)
  local mt = getmetatable(t)
  if mt and mt.__keys then
    if t[key] ~= nil then error('duplicate key: ' .. tostring(key), 0) end
    mt.__keys[#mt.__keys + 1] = key
    mt.__positions[key] = row
  end
  t[key] = value
end
function M.keys(t)
  local mt = type(t) == 'table' and getmetatable(t)
  if mt and mt.__keys then return mt.__keys end
  local keys = vim.tbl_keys(t or {})
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end
function M.is_array(t)
  return type(t) == 'table' and not (getmetatable(t) and getmetatable(t).__keys) and vim.islist(t)
end
function M.error(message, path, row)
  return { severity = 'error', code = 'unsupported-syntax', message = tostring(message), source = { path = path or '', row = row or 0 } }
end
function M.reader(text, mode)
  local p = { text = text, pos = 1, mode = mode or 'js' }
  function p:skip()
    while true do
      local _, e = self.text:find('^%s+', self.pos)
      if e then self.pos = e + 1 end
      local s = self.text:sub(self.pos)
      if s:sub(1, 2) == '//' and self.mode == 'js' then
        self.pos = (self.text:find('\n', self.pos, true) or #self.text) + 1
      elseif s:sub(1, 2) == '/*' and self.mode == 'js' then
        local close = self.text:find('*/', self.pos + 2, true)
        if not close then error('unterminated comment', 0) end
        self.pos = close + 2
      elseif s:sub(1, 1) == '#' and self.mode == 'toml' then
        self.pos = (self.text:find('\n', self.pos, true) or #self.text) + 1
      else break end
    end
  end
  function p:row() return select(2, self.text:sub(1, self.pos - 1):gsub('\n', '')) end
  function p:peek() self:skip(); return self.text:sub(self.pos, self.pos) end
  function p:take(s)
    self:skip()
    if self.text:sub(self.pos, self.pos + #s - 1) == s then self.pos = self.pos + #s; return true end
    return false
  end
  function p:string()
    local q, out = self:peek(), {}
    self.pos = self.pos + 1
    while self.pos <= #self.text do
      local c = self.text:sub(self.pos, self.pos)
      self.pos = self.pos + 1
      if c == q then
        if self.mode == 'yaml' and q == "'" and self.text:sub(self.pos, self.pos) == q then
          out[#out + 1] = q; self.pos = self.pos + 1
        else return table.concat(out) end
      elseif c == '\\' and not (q == "'" and self.mode ~= 'js') then
        local esc = self.text:sub(self.pos, self.pos); self.pos = self.pos + 1
        local escapes = { n = '\n', r = '\r', t = '\t', b = '\b', f = '\f', ['\\'] = '\\', ['"'] = '"', ["'"] = "'", ['/'] = '/' }
        if esc == 'u' then
          local hex = self.text:sub(self.pos, self.pos + 3)
          if not hex:match('^%x%x%x%x$') then error('invalid Unicode escape', 0) end
          out[#out + 1] = vim.fn.nr2char(tonumber(hex, 16)); self.pos = self.pos + 4
        elseif escapes[esc] then out[#out + 1] = escapes[esc]
        else error('unsupported string escape: ' .. esc, 0) end
      else out[#out + 1] = c end
    end
    error('unterminated string', 0)
  end
  function p:key()
    local c = self:peek()
    if c == '"' or c == "'" then return self:string() end
    local key = self.text:sub(self.pos):match(self.mode == 'toml' and '^([%w_%-]+)' or '^([%a_$][%w_$%-]*)')
    if not key then error('expected a static property name', 0) end
    self.pos = self.pos + #key
    return key
  end
  function p:value()
    local c = self:peek()
    if c == '"' or c == "'" then return self:string() end
    if c == '[' then
      self.pos = self.pos + 1
      local out = {}
      if self:take(']') then return out end
      while true do
        out[#out + 1] = self:value()
        if self:take(']') then return out end
        if not self:take(',') then error('expected comma or ]', 0) end
        if self:take(']') then return out end
      end
    end
    if c == '{' then
      self.pos = self.pos + 1
      local out = M.object()
      if self:take('}') then return out end
      while true do
        local row, key = self:row(), self:key()
        if not self:take(self.mode == 'toml' and '=' or ':') then error('expected property separator', 0) end
        M.put(out, key, self:value(), row)
        if self:take('}') then return out end
        if not self:take(',') then error('expected comma or }', 0) end
        if self:take('}') then return out end
      end
    end
    local tail = self.text:sub(self.pos)
    if self.mode == 'js' and tail:match('^require%.resolve%s*%(') then
      -- Recognize a literal path spelling only. Never call require or Node.
      local prefix = tail:match('^(require%.resolve%s*%()')
      self.pos = self.pos + #prefix
      if self:peek() ~= '"' and self:peek() ~= "'" then error('require.resolve must contain one literal path', 0) end
      local path = self:string()
      if not self:take(')') then error('require.resolve must contain one literal path', 0) end
      return path
    end
    if self.mode == 'yaml' then
      local value = tail:match('^([^,%]%}]+)')
      if not value then error('expected value', 0) end
      value = vim.trim(value)
      self.pos = self.pos + #tail:match('^([^,%]%}]+)')
      if value:match('^[!&*]') or value:match('^<<') then error('YAML tags, anchors, aliases and merges require an explicit provider', 0) end
      if value == 'true' then return true end
      if value == 'false' then return false end
      if value == 'null' or value == '~' then return vim.NIL end
      return tonumber(value) or value
    end
    local token = tail:match('^([%w_+%.%-]+)')
    if not token then error('expected a literal; expressions and functions are unsupported', 0) end
    self.pos = self.pos + #token
    if token == 'true' then return true end
    if token == 'false' then return false end
    if token == 'null' then return vim.NIL end
    if tonumber(token:gsub('_', '')) then return tonumber(token:gsub('_', '')) end
    error('dynamic value "' .. token .. '" requires an explicit navigation provider', 0)
  end
  return p
end
function M.parse(text, mode, path)
  local p = M.reader(text, mode)
  local ok, value = pcall(function()
    local v = p:value(); p:skip()
    if p.pos <= #text then error('unexpected trailing syntax', 0) end
    return v
  end)
  if not ok then return nil, { M.error(value, path, p:row()) } end
  return value, {}
end
return M
