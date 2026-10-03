local C = require('md-readable.adapters.common')
local M = { anchor_resolvers = {} }
function M.register_anchor_resolver(adapter, callback)
  M.anchor_resolvers[adapter] = callback
  return function() if M.anchor_resolvers[adapter] == callback then M.anchor_resolvers[adapter] = nil end end
end
function M.anchor(anchor, headings, adapter)
  local custom = M.anchor_resolvers[adapter]
  if custom then return custom(anchor, headings) end
  for _, heading in ipairs(headings or {}) do
    if heading.id == anchor or heading.slug == anchor then
      return heading.range and heading.range.start.row or heading.start_row or heading.row
    end
  end
end
-- Resolved document/asset paths are absolute. Snapshot paths remain relative.
function M.resolve(raw, ctx)
  ctx = ctx or {}
  local forced_path
  if type(raw) == 'table' then
    if raw.type == 'external' then return { type = 'external', url = raw.url } end
    if raw.type == 'unavailable' then return { type = 'unresolved', reason = raw.reason, raw = raw.raw } end
    if raw.type == 'document' then
      forced_path = C.join(ctx.root_dir or '/', raw.path)
      raw = raw.path .. (raw.anchor and '#' .. raw.anchor or '')
    else raw = raw.target or raw.href or raw.path end
  end
  if type(raw) ~= 'string' then return { type = 'unresolved', reason = 'No target', raw = raw } end
  if raw:match('^[%a][%w+.-]*:') or raw:sub(1, 2) == '//' then return { type = 'external', url = raw } end
  local relative, anchor = C.split_target(raw)
  local path
  if forced_path then path = forced_path
  elseif relative == '' then path = ctx.path
  elseif relative:sub(1, 1) == '/' then path = C.join(ctx.root_dir or '/', relative:sub(2))
  else path = C.join(vim.fs.dirname(ctx.path or C.join(ctx.root_dir or '.', 'index.md')), relative) end
  if not path then return { type = 'unresolved', raw = raw, reason = 'No source document path' } end
  local function read(p)
    if ctx.read then return ctx.read(p) end
    local buf = vim.fn.bufnr(p)
    if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
    if vim.fn.filereadable(p) == 1 then return vim.fn.readfile(p) end
  end
  local lines = read(path)
  if not lines then return { type = 'unresolved', path = path, anchor = anchor, raw = raw, reason = 'Local target is unavailable' } end
  if not path:match('%.md$') and not path:match('%.mdx$') then return { type = 'asset', path = path, anchor = anchor } end
  local out = { type = 'document', path = path, anchor = anchor }
  if anchor and anchor ~= '' then
    local headings = path == ctx.path and ctx.headings or nil
    if not headings then
      local ok, parser = pcall(require, 'md-readable.document.parser')
      if ok then headings = parser.parse(lines, { path = path }).headings end
    end
    out.row = M.anchor(anchor, headings, ctx.adapter or (ctx.snapshot and ctx.snapshot.adapterId))
    if out.row == nil then return { type = 'unresolved', path = path, anchor = anchor, raw = raw, reason = 'Anchor is not present: ' .. anchor } end
  end
  return out
end
return M
