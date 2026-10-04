local M = {}
function M.check()
  vim.health.start("md-readable.nvim")
  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("Neovim 0.12 or newer")
  else
    vim.health.error("Neovim >= 0.12 is required")
  end
  for _, item in ipairs({
    { "mmdc", "Mermaid" },
    { "magick", "image conversion" },
    { "curl", "permitted remote images" },
  }) do
    if vim.fn.executable(item[1]) == 1 then
      vim.health.ok(item[1] .. ": available for " .. item[2])
    else
      vim.health.warn(item[1] .. " not found; optional " .. item[2] .. " may be unavailable")
    end
  end
  vim.health.info("Reference plugins are not required. External tools are never automatically installed.")
  local ok, image = pcall(require, "md-readable.providers.image")
  if ok and image.capabilities then
    local capable, reason = image.capabilities()
    if capable then
      vim.health.ok("Terminal image output available")
    else
      vim.health.info("Image fallback: " .. tostring(reason))
    end
  end
  local s = require("md-readable.reader.session").current()
  if s and s.snapshot then
    vim.health.info("Selected adapter: " .. s.snapshot.adapterId)
  end
end
return M
