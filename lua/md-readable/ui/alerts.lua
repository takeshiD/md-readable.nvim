-- Style of callouts (GitHub alerts, MkDocs/Docusaurus admonitions): an icon,
-- a title and a color per kind. The defaults follow GitHub: its Octicons
-- (as Nerd Font glyphs) and its alert colors for dark and light backgrounds.
local M = {}

---@class MdReadableAlertKind
---@field title? string Title shown when the source gives none
---@field icon? string|false Icon before the title; false shows none
---@field color? string "#rrggbb" or a highlight group name

---@alias MdReadableAlertIcons "auto"|"nerd"|"unicode"|false

---@class MdReadableConfigAlerts
---@field enable boolean false shows the plain title without icon or kind color
---@field icons MdReadableAlertIcons "auto": Nerd Font glyphs when mini.icons or nvim-web-devicons is installed
---@field kinds table<string, MdReadableAlertKind>
---@field aliases table<string, string> Other kind names styled as one of `kinds`

M.kinds = { "note", "tip", "important", "warning", "caution" }

-- GitHub's alert icons: Octicons info, light-bulb, report, alert and stop
-- (Nerd Font nf-oct-*, written as UTF-8 bytes).
---@type table<"nerd"|"unicode", table<string, string>>
M.icon_sets = {
  nerd = {
    note = "\239\145\137",
    tip = "\239\144\128",
    important = "\239\148\138",
    warning = "\239\144\161",
    caution = "\239\145\174",
  },
  unicode = { note = "ⓘ", tip = "✦", important = "❢", warning = "⚠", caution = "⊘" },
}

-- GitHub's alert colors (Primer fg.accent/success/done/attention/danger).
---@type table<"dark"|"light", table<string, string>>
M.colors = {
  dark = { note = "#4493f8", tip = "#3fb950", important = "#ab7df8", warning = "#d29922", caution = "#f85149" },
  light = { note = "#0969da", tip = "#1a7f37", important = "#8250df", warning = "#9a6700", caution = "#d1242f" },
}

---@type MdReadableConfigAlerts
M.defaults = {
  enable = true,
  icons = "auto",
  kinds = {
    note = { title = "Note" },
    tip = { title = "Tip" },
    important = { title = "Important" },
    warning = { title = "Warning" },
    caution = { title = "Caution" },
  },
  -- MkDocs, Docusaurus and Obsidian names mapped to the closest GitHub kind.
  aliases = {
    info = "note",
    abstract = "note",
    summary = "note",
    tldr = "note",
    todo = "note",
    example = "note",
    quote = "note",
    cite = "note",
    seealso = "note",
    hint = "tip",
    success = "tip",
    check = "tip",
    done = "tip",
    question = "tip",
    help = "tip",
    faq = "tip",
    attention = "warning",
    danger = "caution",
    error = "caution",
    failure = "caution",
    fail = "caution",
    missing = "caution",
    bug = "caution",
  },
}

---@type boolean?
local icon_plugin

-- Nerd Font glyphs are assumed when an icon plugin built on them is installed.
---@return boolean
local function has_icon_plugin()
  if icon_plugin == nil then
    icon_plugin = pcall(require, "mini.icons") or pcall(require, "nvim-web-devicons")
  end
  return icon_plugin
end

---@param kind string
---@return string
local function group_name(kind)
  return "MdReadableAlert" .. kind:gsub("[^%w]+(%w?)", string.upper):gsub("^%l", string.upper)
end

-- The styled kind of a block kind: itself when configured, else its alias.
---@param opts MdReadableConfigAlerts
---@param kind string
---@return string?
local function resolve(opts, kind)
  kind = kind:lower()
  if opts.kinds[kind] then
    return kind
  end
  local alias = opts.aliases[kind]
  return alias and opts.kinds[alias] and alias or nil
end

---@class MdReadableAlertStyle
---@field icon? string
---@field title? string Configured title of the kind
---@field group string Highlight group of the icon and title

---@param opts? MdReadableConfigAlerts
---@param kind? string Block kind as written ("NOTE", "danger", ...)
---@return MdReadableAlertStyle?
function M.style(opts, kind)
  if not opts or opts.enable == false or not kind then
    return nil
  end
  local name = resolve(opts, kind)
  if not name then
    return nil
  end
  local spec = opts.kinds[name]
  local icon = spec.icon
  if icon == nil and opts.icons ~= false then
    local set = opts.icons == "auto" and (has_icon_plugin() and "nerd" or "unicode") or opts.icons
    icon = (M.icon_sets[set] or {})[name]
  end
  return { icon = icon or nil, title = spec.title, group = group_name(name) }
end

-- Highlight definitions of every configured kind: an explicit color, else
-- GitHub's color for the background, bold.
---@param opts? MdReadableConfigAlerts
---@param background? string "dark" or "light"; defaults to 'background'
---@return table<string, vim.api.keyset.highlight>
function M.highlights(opts, background)
  local result, palette = {}, M.colors[background or vim.o.background] or M.colors.dark
  for kind, spec in pairs((opts or M.defaults).kinds) do
    local color = spec.color or palette[kind]
    if type(color) == "string" and color:match("^#%x%x%x%x%x%x$") then
      result[group_name(kind)] = { fg = tonumber(color:sub(2), 16), bold = true }
    elseif type(color) == "string" and color ~= "" then
      result[group_name(kind)] = { link = color }
    else
      result[group_name(kind)] = { link = "MdReadableCallout" }
    end
  end
  return result
end

---@param opts MdReadableConfigAlerts
---@return string? err
function M.validate(opts)
  if type(opts.enable) ~= "boolean" then
    return "alerts.enable must be true or false"
  end
  if opts.icons ~= false and opts.icons ~= "auto" and not M.icon_sets[opts.icons] then
    return 'alerts.icons must be "auto", "nerd", "unicode" or false'
  end
  for kind, spec in pairs(opts.kinds) do
    if type(spec) ~= "table" then
      return "alerts.kinds." .. kind .. " must be a table"
    end
    if spec.icon ~= nil and spec.icon ~= false and type(spec.icon) ~= "string" then
      return "alerts.kinds." .. kind .. ".icon must be a string or false"
    end
    if spec.color ~= nil and type(spec.color) ~= "string" then
      return "alerts.kinds." .. kind .. ".color must be a string"
    end
    if spec.title ~= nil and type(spec.title) ~= "string" then
      return "alerts.kinds." .. kind .. ".title must be a string"
    end
  end
  for alias, kind in pairs(opts.aliases) do
    if type(kind) ~= "string" then
      return "alerts.aliases." .. alias .. " must be a kind name"
    end
  end
end

return M
