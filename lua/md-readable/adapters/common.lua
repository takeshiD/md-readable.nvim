local L = require("md-readable.parsers.literal")
local M = {}
---@param path string
---@return string # Without "." / resolvable ".." parts or a trailing slash
function M.normalize(path)
  local absolute, parts = path:sub(1, 1) == "/", {}
  for part in path:gsub("\\", "/"):gmatch("[^/]+") do
    if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
      table.remove(parts)
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return (absolute and "/" or "") .. table.concat(parts, "/")
end
---@param a string
---@param b string Absolute b replaces a
---@return string
function M.join(a, b)
  if b:sub(1, 1) == "/" then
    return M.normalize(b)
  end
  return M.normalize((a ~= "" and a .. "/" or "") .. b)
end
---@param root string
---@param path string
---@return string # path unchanged when outside root
function M.relative(root, path)
  root, path = M.normalize(root), M.normalize(path)
  if path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  return path
end
---@param s string Percent-encoded
---@return string
function M.decode(s)
  return (s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end
---@param raw string Link target; the query is dropped
---@return string path
---@return string? anchor
function M.split_target(raw)
  local path, anchor = raw:match("^(.-)#(.*)$")
  path = (path or raw):gsub("%?.*$", "")
  return M.decode(path), anchor and M.decode(anchor) or nil
end
---@param ctx MdReadableNavContext
---@param id string Adapter id
---@return MdReadableNavState
function M.context(ctx, id)
  ---@class MdReadableNavState
  ---@field ctx MdReadableNavContext
  ---@field id string Adapter id
  ---@field diagnostics MdReadableNavDiagnostic[]
  ---@field dependencies string[] Absolute paths, in first-read order
  ---@field dependency_set table<string, true>
  ---@field counter integer Last generated node number
  local state = { ctx = ctx, id = id, diagnostics = {}, dependencies = {}, dependency_set = {}, counter = 0 }
  ---@param code string
  ---@param message string
  ---@param path? string Root-relative source file
  ---@param row? integer 0-based
  ---@param severity? MdReadableNavSeverity Defaults to "warning"
  function state:diagnostic(code, message, path, row, severity)
    self.diagnostics[#self.diagnostics + 1] = {
      severity = severity or "warning",
      code = code,
      message = message,
      source = path and { path = path, row = row or 0 } or nil,
    }
  end
  ---@param path string Absolute
  function state:depend(path)
    if not self.dependency_set[path] then
      self.dependency_set[path] = true
      self.dependencies[#self.dependencies + 1] = path
    end
  end
  ---@param path string Root-relative
  ---@param optional? boolean Suppress the missing-file diagnostic
  ---@return string[]?
  function state:read(path, optional)
    local full = M.join(ctx.root_dir, path)
    self:depend(full)
    local lines
    if ctx.read then
      lines = ctx.read(full)
    else
      local buf = vim.fn.bufnr(full)
      if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      elseif vim.fn.filereadable(full) == 1 then
        lines = vim.fn.readfile(full)
      end
    end
    if type(lines) == "string" then
      lines = vim.split(lines, "\n", { plain = true })
    end
    if not lines and not optional then
      self:diagnostic("missing-file", "File is unavailable: " .. path, path, 0, "error")
    end
    return lines
  end
  ---@param path string Root-relative
  ---@param format "json"|"yaml"|"toml"
  ---@param optional? boolean
  ---@return table?
  function state:data(path, format, optional)
    local lines = self:read(path, optional)
    if not lines then
      return nil
    end
    local value, errors
    if format == "json" then
      local ok
      ok, value = pcall(vim.json.decode, table.concat(lines, "\n"))
      if not ok then
        errors = { L.error(value, path) }
        value = nil
      end
    else
      value, errors = require("md-readable.parsers." .. format).parse(lines, path)
    end
    vim.list_extend(self.diagnostics, errors or {})
    if value ~= nil and type(value) ~= "table" then
      self:diagnostic("config-shape", "Configuration must be an object: " .. path, path, 0, "error")
      return nil
    end
    return value
  end
  ---@param raw any Link spelling from configuration
  ---@param base? string Root-relative directory for relative links
  ---@return MdReadableNavTarget
  function state:target(raw, base)
    if type(raw) ~= "string" or raw == "" then
      return { type = "unavailable", raw = tostring(raw or ""), reason = "No local document (draft)" }
    end
    if raw:match("^[%a][%w+.-]*:") or raw:sub(1, 2) == "//" then
      return { type = "external", url = raw }
    end
    local path, anchor = M.split_target(raw)
    path = M.join(base or "", path)
    if path:sub(1, 1) == "/" then
      path = M.relative(ctx.root_dir, path)
    end
    if not self:read(path, true) then
      self:diagnostic("missing-document", "Document is not available locally: " .. path, path)
      return { type = "unavailable", raw = raw, reason = "Missing local document: " .. path }
    end
    return { type = "document", path = path, anchor = anchor }
  end
  ---@param title any
  ---@param target? MdReadableNavTarget
  ---@param children? MdReadableNavNode[]
  ---@param source? MdReadableNavSource
  ---@param id? string Defaults to "<adapter>:<counter>"
  ---@return MdReadableNavNode
  function state:node(title, target, children, source, id)
    self.counter = self.counter + 1
    return {
      id = id or self.id .. ":" .. self.counter,
      title = tostring(title or ""),
      target = target,
      children = children or {},
      source = source,
    }
  end
  ---@param trees? MdReadableNavTree[] nil reports failure
  ---@param origin? MdReadableNavOrderOrigin Defaults to "declared"
  ---@return MdReadableNavResult
  function state:finish(trees, origin)
    if not trees then
      local status = "error"
      for _, d in ipairs(self.diagnostics) do
        if
          d.code == "unsupported-syntax"
          or d.code == "dynamic-config"
          or d.code == "astro-provider-required"
          or d.code == "custom-content-loader"
          or d.code == "locale-provider-required"
        then
          status = "unsupported"
          break
        end
      end
      return { status = status, diagnostics = self.diagnostics, dependencies = self.dependencies }
    end
    local snapshot = {
      schemaVersion = 1,
      rootDir = ctx.root_dir,
      adapterId = id,
      trees = trees,
      orderOrigin = origin or "declared",
      diagnostics = self.diagnostics,
    }
    local valid, errors = require("md-readable.navigation.model").validate(snapshot)
    vim.list_extend(self.diagnostics, errors)
    if not valid then
      return { status = "error", diagnostics = self.diagnostics, dependencies = self.dependencies }
    end
    return {
      status = #self.diagnostics > 0 and "partial" or "ok",
      snapshot = snapshot,
      diagnostics = self.diagnostics,
      dependencies = self.dependencies,
    }
  end
  ---@param path string Root-relative SUMMARY.md
  ---@param base string Root-relative directory for links
  ---@param title? string
  ---@param tree_id? string
  ---@return MdReadableNavTree?
  function state:summary(path, base, title, tree_id)
    local lines = self:read(path)
    if not lines then
      return nil
    end
    local raw, diagnostics = require("md-readable.parsers.summary").parse(lines, path)
    vim.list_extend(self.diagnostics, diagnostics)
    ---@param nodes MdReadableParseSummaryItem[]
    ---@return MdReadableNavNode[]
    local function convert(nodes)
      local out, group = {}, nil
      for _, item in ipairs(nodes) do
        if item.kind == "heading" then
          if not (item.first and item.level == 1) and (id ~= "mdbook" or item.level == 1) then
            group = self:node(item.title, nil, {}, item.source)
            out[#out + 1] = group
          end
        else
          local target = item.kind == "link" and self:target(item.target, base) or nil
          local node = self:node(
            id == "gitbook" and (item.link_title or item.title) or item.title,
            target,
            convert(item.children),
            item.source
          )
          table.insert(group and group.children or out, node)
        end
      end
      return out
    end
    return { id = tree_id or "main", title = title or "Contents", items = convert(raw) }
  end
  return state
end
-- MkDocs-style nav: a sequence of paths and single-key {title = path|nav} maps.
---@param state MdReadableNavState
---@param data any
---@param base string Root-relative docs directory
---@param source? MdReadableNavSource
---@return MdReadableNavNode[]
function M.nav(state, data, base, source)
  local out = {}
  ---@param title? string
  ---@param value any
  local function add(title, value)
    if type(value) == "string" then
      out[#out + 1] = state:node(title or value, state:target(value, base), {}, source)
    elseif type(value) == "table" then
      out[#out + 1] = state:node(title or "Section", nil, M.nav(state, value, base, source), source)
    else
      state:diagnostic("invalid-nav", "Navigation entry must be a path or a list", source and source.path)
    end
  end
  if type(data) ~= "table" then
    state:diagnostic("invalid-nav", "nav must be a sequence")
    return out
  end
  if L.is_array(data) then
    for _, item in ipairs(data) do
      if type(item) == "string" then
        add(nil, item)
      elseif type(item) == "table" then
        for _, key in ipairs(L.keys(item)) do
          local mt = getmetatable(item)
          if source and mt and mt.__positions then
            source = { path = source.path, row = mt.__positions[key] }
          end
          add(key, item[key])
        end
      else
        state:diagnostic("invalid-nav", "Invalid navigation entry")
      end
    end
  else
    for _, key in ipairs(L.keys(data)) do
      add(key, data[key])
    end
  end
  return out
end
---@param state MdReadableNavState
---@param dir string Root-relative
---@return string[] # Sorted root-relative .md/.mdx paths
function M.files(state, dir)
  local full = M.join(state.ctx.root_dir, dir)
  state:depend(full)
  local files = state.ctx.list and state.ctx.list(full) or vim.fn.globpath(full, "**/*", false, true)
  local out = {}
  for _, path in ipairs(files or {}) do
    if path:match("%.md$") or path:match("%.mdx$") then
      out[#out + 1] = M.relative(state.ctx.root_dir, path)
    end
  end
  table.sort(out)
  return out
end
return M
