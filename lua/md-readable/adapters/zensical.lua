local C = require("md-readable.adapters.common")
local M = {}
function M.parse(ctx)
  local s = C.context(ctx, "zensical")
  local path = ctx.config_path or (s:read("zensical.toml", true) and "zensical.toml" or "mkdocs.yml")
  local config = s:data(path, path:match("%.toml$") and "toml" or "yaml")
  if not config then
    return s:finish()
  end
  if path:match("%.toml$") then
    config = config.project
    if type(config) ~= "table" then
      s:diagnostic("missing-project", "Zensical TOML needs [project]", path, 0, "error")
      return s:finish()
    end
  end
  return require("md-readable.adapters.mkdocs").from_config(s, config, path)
end
return M
