local C = require("md-readable.adapters.common")
local M = {}
---@param ctx MdReadableNavContext
---@return MdReadableNavResult
function M.parse(ctx)
  local s = C.context(ctx, "mdbook")
  local config = s:data(ctx.config_path or "book.toml", "toml")
  if not config then
    return s:finish()
  end
  local book = config.book or {}
  local base = book.src or "src"
  if config.preprocessor then
    s:diagnostic(
      "dynamic-preprocessor",
      "mdBook preprocessors are not run; use a navigation provider for generated chapters",
      "book.toml"
    )
  end
  local tree = s:summary(C.join(base, "SUMMARY.md"), base, book.title)
  return s:finish(tree and { tree })
end
return M
