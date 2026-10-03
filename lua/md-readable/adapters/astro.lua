local C = require('md-readable.adapters.common')
local L = require('md-readable.parsers.literal')
local Static = require('md-readable.parsers.sidebar_static')
local M = {}
function M.parse(ctx)
  local s = C.context(ctx, 'astro')
  local config_path = ctx.config_path
  if not config_path then
    for _, path in ipairs({ 'astro.config.mjs', 'astro.config.ts', 'astro.config.js' }) do if s:read(path, true) then config_path = path; break end end
  end
  local lines = config_path and s:read(config_path)
  if not lines then s:diagnostic('astro-provider-required', 'General Astro sites require an explicit navigation provider', config_path, 0, 'error'); return s:finish() end
  local options, diagnostics = Static.extract(lines, 'starlight', 'call', config_path)
  vim.list_extend(s.diagnostics, diagnostics)
  if not options then
    s:diagnostic('astro-provider-required', 'Starlight options must be literal; general Astro/custom loaders require a provider', config_path, 0, 'error')
    return s:finish()
  end
  if options.locales then s:diagnostic('locale-provider-required', 'Starlight locale collections require an explicit provider', config_path, 0, 'error'); return s:finish() end
  for _, content_config in ipairs({ 'src/content.config.ts', 'src/content.config.js', 'src/content/config.ts' }) do
    local content = s:read(content_config, true)
    if content then
      local text = table.concat(content, '\n')
      if text:match('loader%s*:') and not text:match('docsLoader%s*%(') then
        s:diagnostic('custom-content-loader', 'Custom content loaders are not executed; use a provider', content_config, 0, 'error'); return s:finish()
      end
    end
  end
  local base = ctx.docs_dir or 'src/content/docs'
  local docs, by_slug = {}, {}
  for _, path in ipairs(C.files(s, base)) do
    local metadata, errors = require('md-readable.parsers.frontmatter').parse(s:read(path) or {}, path)
    vim.list_extend(s.diagnostics, errors); metadata = metadata or {}
    local relative = C.relative(base, path):gsub('%.mdx?$', '')
    local slug = metadata.slug or relative:gsub('/index$', '')
    if slug == 'index' then slug = '' end
    local doc = { path = path, slug = slug, relative = relative, title = metadata.title or relative, metadata = metadata }
    if by_slug[slug] then s:diagnostic('duplicate-slug', 'Multiple documents have the same Starlight slug: ' .. slug, path)
    else docs[#docs + 1] = doc; by_slug[slug] = doc end
  end
  local function document(slug, label)
    slug = slug:gsub('^/', ''):gsub('/$', '')
    local doc = by_slug[slug]
    if not doc then s:diagnostic('unknown-slug', 'Unresolved Starlight slug: ' .. slug); return s:node(label or slug, { type = 'unavailable', raw = slug, reason = 'Unknown local slug' }) end
    local sidebar = doc.metadata.sidebar or {}
    local node = s:node(label or sidebar.label or doc.title, doc.metadata.draft and { type = 'unavailable', raw = slug, reason = 'Draft page' } or { type = 'document', path = doc.path }, {}, { path = doc.path })
    node.position = sidebar.order or math.huge; node.sort_key = doc.relative
    return node
  end
  local auto
  auto = function(directory)
    directory = C.normalize(directory or '')
    local out, dirs = {}, {}
    for _, doc in ipairs(docs) do
      local relative = directory == '' and doc.relative or (doc.relative:sub(1, #directory + 1) == directory .. '/' and doc.relative:sub(#directory + 2))
      if relative and not (doc.metadata.sidebar or {}).hidden and not doc.metadata.draft then
        local sub = relative:match('^([^/]+)/')
        if sub then dirs[sub] = true else out[#out + 1] = document(doc.slug) end
      end
    end
    for _, name in ipairs(L.keys(dirs)) do
      local node = s:node(name, nil, auto(C.join(directory, name))); node.sort_key = name; out[#out + 1] = node
    end
    table.sort(out, function(a, b)
      if (a.position or math.huge) ~= (b.position or math.huge) then return (a.position or math.huge) < (b.position or math.huge) end
      return (a.sort_key or '') < (b.sort_key or '')
    end)
    return out
  end
  local convert
  convert = function(items)
    local out = {}
    for _, item in ipairs(items or {}) do
      if type(item) == 'string' then out[#out + 1] = document(item)
      elseif type(item) ~= 'table' then s:diagnostic('invalid-sidebar', 'Starlight sidebar entry must be a string or object', config_path)
      elseif item.slug then out[#out + 1] = document(item.slug, item.label)
      elseif item.link then
        local node
        if item.link:sub(1, 1) == '/' and item.link:sub(1, 2) ~= '//' then node = document(item.link, item.label)
        else node = s:node(item.label or item.link, s:target(item.link, base)) end
        out[#out + 1] = node
      elseif item.items then out[#out + 1] = s:node(item.label or 'Section', nil, convert(item.items))
      elseif item.autogenerate then
        local children = auto(item.autogenerate.directory)
        if item.label then out[#out + 1] = s:node(item.label, nil, children) else vim.list_extend(out, children) end
      else s:diagnostic('invalid-sidebar', 'Unknown Starlight sidebar item', config_path) end
    end
    return out
  end
  return s:finish({ { id = 'main', title = options.title or 'Contents', items = options.sidebar and convert(options.sidebar) or auto('') } }, options.sidebar and 'declared' or 'generated')
end
return M
