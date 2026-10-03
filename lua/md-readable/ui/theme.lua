local M = {}
local windows = {}
local defaults = {
  MdReadableHeading = { link = "Title" },
  MdReadableLink = { link = "Underlined" },
  MdReadableCode = { link = "String" },
  MdReadableCodeBlock = { link = "NormalFloat" },
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
  MdReadableMinimapCurrent = { link = "CursorLine" },
  MdReadableGitAdd = { link = "DiffAdd" },
  MdReadableGitChange = { link = "DiffChange" },
  MdReadableGitDelete = { link = "DiffDelete" },
}
for level = 1, 6 do
  defaults["MdReadableHeading" .. level] = { link = "Title" }
end
local presets = {
  dark = { fg = "#d5d8de", bg = "#20242c", accent = "#9cc4ef", muted = "#959fad", code = "#b8d7a3" },
  light = { fg = "#30343b", bg = "#faf8f2", accent = "#205d96", muted = "#68717b", code = "#346534" },
}

function M.setup()
  for name, value in pairs(defaults) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", value, { default = true }))
  end
  local group = vim.api.nvim_create_augroup("MdReadableThemes", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      for name, value in pairs(defaults) do
        vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", value, { default = true }))
      end
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

function M.apply(win, name, opts)
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
  local definitions = vim.deepcopy(defaults)
  local palette = presets[name]
  if palette then
    definitions.Normal = { fg = palette.fg, bg = palette.bg }
    definitions.NormalNC = definitions.Normal
    definitions.NormalFloat = definitions.Normal
    definitions.EndOfBuffer = { fg = palette.bg, bg = palette.bg }
    definitions.MdReadableHeading = { fg = palette.accent, bold = true }
    for level = 1, 6 do
      definitions["MdReadableHeading" .. level] = definitions.MdReadableHeading
    end
    definitions.MdReadableLink = { fg = palette.accent, underline = true }
    definitions.MdReadableCode = { fg = palette.code }
    definitions.MdReadableCodeBlock = { fg = palette.code, bg = palette.bg }
    for _, group in ipairs({ "Quote", "Rule", "Omission", "TableBorder" }) do
      definitions["MdReadable" .. group] = { fg = palette.muted }
    end
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

function M.close(win)
  local state = windows[win]
  if state and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_hl_ns(win, state.previous_ns)
  end
  windows[win] = nil
end

return M
