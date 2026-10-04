-- Named reader actions for buffer-local keymaps. Each action runs the same
-- code path as the matching :MdReadable subcommand.
local M = {}
---@class MdReadableKeymapAction
---@field callback fun()
---@field desc string
---@param name string :MdReadable subcommand
---@param ... string Subcommand arguments
---@return fun()
local function command(name, ...)
  local args = { ... }
  return function()
    require("md-readable.errors").report(require("md-readable").action, name, args, {})
  end
end
---@return MdReadableCommandOpts
local function visual_range()
  local first, last = vim.fn.line("v"), vim.fn.line(".")
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  return { range = 2, line1 = math.min(first, last), line2 = math.max(first, last) }
end

M.close = { callback = command("close"), desc = "Close reading view" }
M.open = { callback = command("open"), desc = "Open link, cell, tab or details at cursor" }
M.source = { callback = command("source"), desc = "Jump to the source position" }
M.heading_next = { callback = command("heading-next"), desc = "Next heading" }
M.heading_prev = { callback = command("heading-prev"), desc = "Previous heading" }
M.next_page = { callback = command("next"), desc = "Next page" }
M.prev_page = { callback = command("prev"), desc = "Previous page" }
M.toggle_nav = { callback = command("nav"), desc = "Toggle book navigation" }
M.outline = { callback = command("outline"), desc = "Page headings" }
M.select = { callback = command("select"), desc = "Select navigation adapter or tree" }
M.links = { callback = command("links"), desc = "Document links" }
M.search = { callback = command("search"), desc = "Search source including omitted text" }
---@type MdReadableKeymapAction
M.toggle_focus = {
  callback = function()
    local mode = vim.api.nvim_get_mode().mode
    local visual = mode == "v" or mode == "V" or mode == "\22"
    local args, opts = { visual and "on" or "toggle" }, visual and visual_range() or {}
    require("md-readable.errors").report(require("md-readable").action, "focus", args, opts)
  end,
  desc = "Toggle Focus (Visual: focus the selected lines)",
}
M.toggle_minimap = { callback = command("minimap", "toggle"), desc = "Toggle minimap" }
M.focus_minimap = { callback = command("minimap", "focus"), desc = "Focus minimap" }
M.expand = { callback = command("expand"), desc = "Expand or collapse omitted content" }
M.next_tab = { callback = command("tab"), desc = "Select the next static tab" }
M.refresh = { callback = command("refresh"), desc = "Reload navigation and redraw" }
M.diagnostics = { callback = command("diagnostics"), desc = "Navigation and media diagnostics" }
---@type MdReadableKeymapAction
M.show_help = {
  callback = function()
    require("md-readable.keymaps").help()
  end,
  desc = "Show reader keymaps",
}

-- Accepts "actions.heading_next", "heading_next" or "heading-next".
---@param name any Action name; non-strings yield nil
---@return MdReadableKeymapAction? action
---@return string? key Normalized name
function M.get(name)
  if type(name) ~= "string" then
    return nil
  end
  local key = name:gsub("^actions%.", ""):gsub("-", "_")
  return M[key] ~= nil and type(M[key]) == "table" and M[key] or nil, key
end
---@return string[]
function M.names()
  local names = {}
  for name, value in pairs(M) do
    if type(value) == "table" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end
return M
