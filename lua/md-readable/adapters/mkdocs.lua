local C = require("md-readable.adapters.common")
local M = {}
function M.from_config(s, config, path)
  local base = config.docs_dir or "docs"
  if config.INHERIT then
    s:diagnostic("config-inheritance", "INHERIT is not expanded; use a flattened config or explicit provider", path)
  end
  if config.plugins then
    s:diagnostic("dynamic-plugins", "Plugins are not executed; navigation reflects only static configuration", path)
  end
  local items, origin
  if config.nav == nil then
    s:diagnostic(
      "inferred-navigation",
      "nav is absent: filesystem ordering is inferred, not the SSG build output",
      path
    )
    items, origin = {}, "inferred"
    for _, file in ipairs(C.files(s, base)) do
      items[#items + 1] = s:node(file, s:target(file, ""))
    end
  else
    items, origin = C.nav(s, config.nav, base, { path = path }), "declared"
  end
  return s:finish({ { id = "main", title = config.site_name or "Contents", items = items } }, origin)
end
function M.parse(ctx)
  local s = C.context(ctx, "mkdocs")
  local path = ctx.config_path or "mkdocs.yml"
  local config = s:data(path, "yaml")
  if not config then
    return s:finish()
  end
  return M.from_config(s, config, path)
end
return M
