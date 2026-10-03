local M = {}
-- Use as Snacks.picker.files({ preview = require(...).preview() }) or as
-- picker.preview in Snacks setup. Context reset may replace its scratch buffer.
function M.preview(opts)
  opts = opts or {}
  local engines = {}
  return function(ctx)
    local core = require("md-readable.integrations.preview")
    local util = require("snacks.picker.util")
    local path = util.path(ctx.item)
    local engine = engines[ctx.win]
    if not engine or engine.closed then
      engine = core.new(opts)
      engines[ctx.win] = engine
    end
    local function fallback()
      return require("snacks.picker.preview").file(ctx)
    end
    local kind = core.kind(path)
    if not kind or (kind == "image" and not core.capable(opts)) then
      engine:clear()
      return fallback()
    end
    ctx.preview:reset()
    ctx.preview:set_title(ctx.item.title or vim.fn.fnamemodify(path, ":t"))
    ctx.preview:minimal()
    return engine:show(path, ctx.buf, ctx.win, ctx.item.pos, fallback)
  end
end
return M
