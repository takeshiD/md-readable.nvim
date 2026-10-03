local M = {}
function M.follow(session, link)
  local resolved = require("md-readable.navigation.resolver").resolve(link.target, {
    path = vim.api.nvim_buf_get_name(session.source_buf),
    root_dir = session.snapshot and session.snapshot.rootDir,
    snapshot = session.snapshot,
    headings = session.document.headings,
  })
  if not resolved then
    vim.notify("md-readable: unresolved link", vim.log.levels.WARN)
    return
  end
  if resolved.type == "document" then
    session:navigate(resolved.path, resolved.anchor)
  elseif resolved.type == "external" then
    vim.ui.open(resolved.url)
  elseif resolved.type == "asset" then
    vim.ui.open(resolved.path)
  else
    vim.notify("md-readable: " .. (resolved.reason or "unresolved link"), vim.log.levels.WARN)
  end
end
function M.open(session)
  vim.ui.select(session.document.links or {}, {
    prompt = "Document links",
    format_item = function(item)
      return string.format("[%s] %s → %s", item.kind or "link", item.text or "", tostring(item.target))
    end,
  }, function(item)
    if item and not session.closed then
      M.follow(session, item)
    end
  end)
end
return M
