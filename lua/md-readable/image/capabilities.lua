local M = {}

---@param env table<string,string?>
---@param attached boolean
---@return boolean supported
---@return string? reason
function M.detect(env, attached)
  if not attached then
    return false, "inline images require an attached terminal UI"
  end
  local program = (env.TERM_PROGRAM or ""):lower()
  -- Images are drawn with Kitty Unicode placeholders (see image/display.lua),
  -- which Kitty and Ghostty implement and WezTerm does not.
  local supported = program == "kitty"
    or program == "ghostty"
    or env.KITTY_WINDOW_ID ~= nil
    or env.GHOSTTY_RESOURCES_DIR ~= nil
  if not supported then
    if program == "wezterm" or env.WEZTERM_EXECUTABLE ~= nil then
      return false, "WezTerm does not support Kitty Unicode placeholders"
    end
    return false, "terminal does not advertise Kitty graphics support"
  end
  return true
end

---@return boolean supported
---@return string? reason
function M.get()
  if not vim.api.nvim_ui_send then
    return false, "inline images require Neovim 0.12 or newer"
  end
  return M.detect(vim.env, #vim.api.nvim_list_uis() > 0)
end

return M
