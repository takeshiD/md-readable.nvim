local C = require("md-readable.adapters.common")
local M = {}
function M.parse(ctx)
  local s = C.context(ctx, "honkit")
  local config_path = ctx.config_path or "book.json"
  if config_path:match("%.[jt]s$") or s:read("book.js", true) then
    s:diagnostic(
      "dynamic-config",
      "HonKit JavaScript configuration is not executed; export a static JSON snapshot/provider",
      config_path,
      0,
      "error"
    )
    return s:finish()
  end
  local config = s:data(config_path, "json", not ctx.config_path) or {}
  if #s.diagnostics > 0 then
    return s:finish()
  end
  if config.plugins and #config.plugins > 0 then
    s:diagnostic("dynamic-plugins", "Plugin-generated navigation requires an explicit provider", config_path)
  end
  local base = config.root or ""
  local tree = s:summary(C.join(base, (config.structure or {}).summary or "SUMMARY.md"), base, config.title)
  return s:finish(tree and { tree })
end
return M
