local M = {}
---@class MdReadableThemeWindowState
---@field ns integer Highlight namespace of the window
---@field previous_ns integer Namespace restored on close (-1 for global)
---@field name? string Theme name
---@field opts? MdReadableConfig
---@field groups? table<string, vim.api.keyset.highlight> Groups defined in `ns`
---@class MdReadableThemePalette
---@field fg string "#rrggbb"
---@field bg string
---@field accent string
---@field muted string
---@field code string
---@field link string
---@field headings string[] One color per heading level
---@type table<integer, MdReadableThemeWindowState>
local windows = {}
local initialized = false
---@type table<string, vim.api.keyset.highlight>
local defaults = {
  MdReadableHeading = { link = "Title" },
  MdReadableTableBorder = { link = "Comment" },
  MdReadableTableHeader = { bold = true },
  MdReadableQuote = { link = "Comment" },
  MdReadableBold = { bold = true },
  MdReadableItalic = { italic = true },
  MdReadableRule = { link = "Comment" },
  MdReadableStrike = { strikethrough = true },
  MdReadableMuted = { link = "Comment" },
  MdReadableTabActive = { link = "TabLineSel" },
  MdReadableCheckbox = { link = "Special" },
  MdReadableOmission = { link = "Comment" },
  MdReadableCallout = { link = "Special" },
  MdReadableLinkIcon = { link = "Comment" },
  MdReadableFootnote = { link = "Special" },
  MdReadableMinimapCurrent = { link = "CursorLine" },
  MdReadableMinimapCode = { link = "MdReadableCode" },
}
-- Used when the colorscheme gives every Markdown heading level the same style
-- (the built-in default does). Groups are chosen to differ in common schemes.
local heading_fallbacks = { "Title", "Function", "String", "DiagnosticWarn", "Constant", "Comment" }
---@type table<string, MdReadableThemePalette>
local presets = {
  dark = {
    fg = "#d5d8de",
    bg = "#20242c",
    accent = "#9cc4ef",
    muted = "#959fad",
    code = "#b8d7a3",
    link = "#79c0ff",
    headings = { "#f2f4f8", "#9cc4ef", "#e5c890", "#d4a6e0", "#9fd5cf", "#959fad" },
  },
  light = {
    fg = "#30343b",
    bg = "#faf8f2",
    accent = "#205d96",
    muted = "#68717b",
    code = "#346534",
    link = "#0b62c4",
    headings = { "#16191d", "#205d96", "#8a5a00", "#7a3e9d", "#1f6f6a", "#68717b" },
  },
}

---@param name string
---@return vim.api.keyset.get_hl_info
local function resolve(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end
---@param fg integer 0xRRGGBB
---@param bg integer 0xRRGGBB
---@param alpha number Weight of `fg` in [0, 1]
---@return integer
local function blend(fg, bg, alpha)
  ---@param shift integer
  ---@return integer
  local function channel(shift)
    local a, b = math.floor(fg / shift) % 256, math.floor(bg / shift) % 256
    return math.floor(a * alpha + b * (1 - alpha) + 0.5)
  end
  return channel(65536) * 65536 + channel(256) * 256 + channel(1)
end

-- Definitions derived from the active colorscheme.
---@return table<string, vim.api.keyset.highlight>
function M.highlights()
  local result = vim.deepcopy(defaults)
  local levels, distinct = {}, false
  for level = 1, 6 do
    levels[level] = resolve("@markup.heading." .. level .. ".markdown")
    distinct = distinct or not vim.deep_equal(levels[1], levels[level])
  end
  for level = 1, 6 do
    local value = distinct and (levels[level].fg or levels[level].bg) and levels[level]
      or resolve(heading_fallbacks[level])
    value = vim.deepcopy(value)
    value.cterm, value.default = nil, nil
    value.bold = true
    if not value.fg and not value.bg then
      value = { link = "Title" }
    end
    result["MdReadableHeading" .. level] = value
  end
  local link = resolve("@markup.link.label")
  local fallback = resolve("Identifier")
  result.MdReadableLink = { fg = link.fg or fallback.fg, underline = true }
  if not result.MdReadableLink.fg then
    result.MdReadableLink = { link = "Underlined" }
  end
  local normal, comment, str = resolve("Normal"), resolve("Comment"), resolve("String")
  result.MdReadableCode = { fg = str.fg }
  if comment.fg and normal.bg then
    result.MdReadableCode.bg = blend(comment.fg, normal.bg, 0.2)
  end
  if not str.fg and not result.MdReadableCode.bg then
    result.MdReadableCode = { link = "String" }
  end
  local code = require("md-readable.config").options.code
  for group, value in pairs(require("md-readable.ui.code_theme").highlights(code, normal.bg)) do
    result[group] = value
  end
  return result
end

local function define_global()
  for name, value in pairs(M.highlights()) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", value, { default = true }))
  end
end

function M.setup()
  initialized = true
  define_global()
  local group = vim.api.nvim_create_augroup("MdReadableThemes", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      define_global()
      for win, state in pairs(windows) do
        if vim.api.nvim_win_is_valid(win) then
          M.apply(win, state.name, state.opts)
        else
          windows[win] = nil
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      windows[tonumber(event.match)] = nil
    end,
  })
end

---@param win integer
---@param name? string "default", "dark" or "light"
---@param opts? MdReadableConfig
---@return integer? ns
---@return string? err
function M.apply(win, name, opts)
  if not initialized then
    M.setup()
  end
  if not vim.api.nvim_win_is_valid(win) then
    return nil, "reading window is closed"
  end
  name, opts = name or "default", opts or {}
  if name ~= "default" and not presets[name] then
    return nil, "unknown reading theme: " .. name
  end
  local state = windows[win]
  if not state then
    local old = vim.api.nvim_get_hl_ns and vim.api.nvim_get_hl_ns({ winid = win }) or -1
    state = { ns = vim.api.nvim_create_namespace("MdReadableTheme" .. win), previous_ns = old }
    windows[win] = state
  end
  state.name, state.opts = name, vim.deepcopy(opts)
  -- Clear previous overrides before reapplying; empty definitions inherit globally.
  for group in pairs(state.groups or {}) do
    vim.api.nvim_set_hl(state.ns, group, {})
  end
  -- The default theme keeps the global MdReadable* groups, so user overrides
  -- of those groups apply to reading windows too. Code block groups are the
  -- exception (set per window from the session's code options); override them
  -- through code.colors or the highlights option.
  local definitions = {}
  local palette = presets[name]
  if palette then
    definitions = M.highlights()
    definitions.Normal = { fg = palette.fg, bg = palette.bg }
    definitions.NormalNC = definitions.Normal
    definitions.NormalFloat = definitions.Normal
    definitions.EndOfBuffer = { fg = palette.bg, bg = palette.bg }
    definitions.MdReadableHeading = { fg = palette.accent, bold = true }
    for level = 1, 6 do
      definitions["MdReadableHeading" .. level] = { fg = palette.headings[level], bold = true }
    end
    definitions.MdReadableLink = { fg = palette.link, underline = true }
    definitions.MdReadableCode =
      { fg = palette.code, bg = blend(tonumber(palette.muted:sub(2), 16), tonumber(palette.bg:sub(2), 16), 0.15) }
    for _, group in ipairs({ "Quote", "Rule", "Omission", "TableBorder", "Muted", "LinkIcon" }) do
      definitions["MdReadable" .. group] = { fg = palette.muted }
    end
  end
  -- Code block colors follow this session's options, on any reading theme.
  local base = palette and tonumber(palette.bg:sub(2), 16) or resolve("Normal").bg
  local text = palette and tonumber(palette.code:sub(2), 16) or nil
  for group, value in pairs(require("md-readable.ui.code_theme").highlights(opts.code, base, text)) do
    definitions[group] = value
  end
  for group, value in pairs(opts.highlights or {}) do
    definitions[group] = value
  end
  for group, value in pairs(definitions) do
    vim.api.nvim_set_hl(state.ns, group, value)
  end
  state.groups = definitions
  vim.api.nvim_win_set_hl_ns(win, state.ns)
  vim.api.nvim_exec_autocmds("User", { pattern = "MdReadableThemeChanged", modeline = false, data = { win = win } })
  return state.ns
end

---@param win integer
function M.close(win)
  local state = windows[win]
  if state and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_hl_ns(win, state.previous_ns)
  end
  -- The namespace is keyed by window id and reused if the window reads again.
  for group in pairs(state and state.groups or {}) do
    vim.api.nvim_set_hl(state.ns, group, {})
  end
  windows[win] = nil
end

return M
