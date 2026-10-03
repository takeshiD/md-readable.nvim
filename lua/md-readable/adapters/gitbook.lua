local C = require('md-readable.adapters.common')
local M = {}
function M.parse(ctx)
  local s = C.context(ctx, 'gitbook')
  local trees = {}
  local function space(directory, key, title)
    if type(directory) ~= 'string' then
      s:diagnostic('unsynced-space', 'Space is not synced locally: ' .. title)
      trees[#trees + 1] = { id = key, title = title, items = { s:node(title, { type = 'unavailable', raw = key, reason = 'Space is not synced locally' }) } }
      return
    end
    local config_path = C.join(directory, '.gitbook.yaml')
    local cfg = {}
    if s:read(config_path, true) then cfg = s:data(config_path, 'yaml'); if not cfg then return end end
    local base = C.join(directory, cfg.root or '')
    local tree = s:summary(C.join(base, (cfg.structure or {}).summary or 'SUMMARY.md'), base, title, key)
    if tree then
      local seen = {}
      for _, node in ipairs(require('md-readable.navigation.index').build(tree).order) do
        if node.target and node.target.type == 'document' then
          if seen[node.target.path] then s:diagnostic('duplicate-document', 'GitBook SUMMARY may only include each document once: ' .. node.target.path)
          else seen[node.target.path] = true end
        end
      end
      trees[#trees + 1] = tree
    end
    if cfg.redirects then s:diagnostic('redirects-not-applied', 'Space redirects are not applied to local document links', config_path) end
  end
  local site_path = ctx.config_path or 'gitbook-docs.yaml'
  if site_path:match('gitbook%-docs%.ya?ml$') and s:read(site_path, true) then
    local config = s:data(site_path, 'yaml')
    if not config then return s:finish() end
    if type(config.site) ~= 'table' or type(config.site.structure) ~= 'table' then
      s:diagnostic('site-structure', 'gitbook-docs.yaml requires site.structure', site_path, 0, 'error'); return s:finish()
    end
    local function visit(items)
      for _, item in ipairs(items or {}) do
        if item.type == 'space' then space(item.content and item.content.directory, item.key or item.title, item.title or item.key)
        elseif item.children then visit(item.children)
        else s:diagnostic('unknown-site-entry', 'Unsupported GitBook site structure entry', site_path) end
      end
    end
    visit(config.site and config.site.structure)
  else
    local directory = ctx.config_path and C.relative(ctx.root_dir, vim.fs.dirname(ctx.config_path)) or ''
    if directory == '.' then directory = '' end
    space(directory, 'main', 'Contents')
  end
  return s:finish(trees)
end
return M
