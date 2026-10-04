-- Code block colors: a background set apart from the text (Shiki-like) and
-- optional syntax palettes that apply to code blocks only.
local M = {}
---@alias MdReadableCodeRole "comment"|"keyword"|"string"|"number"|"constant"|"func"|"type"|"variable"|"parameter"|"property"|"operator"|"punctuation"|"tag"
---@class MdReadableCodePalette
---@field bg string "#rrggbb"
---@field fg string
---@field label? string Language label; defaults to `comment`
---@field comment? string
---@field keyword? string
---@field string? string
---@field number? string
---@field constant? string
---@field func? string
---@field type? string
---@field variable? string
---@field parameter? string
---@field property? string
---@field operator? string
---@field punctuation? string
---@field tag? string

---@type MdReadableCodeRole[]
M.roles = {
  "comment",
  "keyword",
  "string",
  "number",
  "constant",
  "func",
  "type",
  "variable",
  "parameter",
  "property",
  "operator",
  "punctuation",
  "tag",
}

-- Taken from the Shiki themes of the same name (catppuccin: Mocha, tokyonight:
-- Night), reduced to the roles above.
---@type table<string, MdReadableCodePalette>
M.presets = {
  ["github-dark"] = {
    bg = "#24292e",
    fg = "#e1e4e8",
    comment = "#6a737d",
    keyword = "#f97583",
    string = "#9ecbff",
    number = "#79b8ff",
    constant = "#79b8ff",
    func = "#b392f0",
    type = "#b392f0",
    variable = "#e1e4e8",
    parameter = "#ffab70",
    property = "#79b8ff",
    operator = "#f97583",
    punctuation = "#e1e4e8",
    tag = "#85e89d",
  },
  ["github-light"] = {
    bg = "#ffffff",
    fg = "#24292e",
    comment = "#6a737d",
    keyword = "#d73a49",
    string = "#032f62",
    number = "#005cc5",
    constant = "#005cc5",
    func = "#6f42c1",
    type = "#6f42c1",
    variable = "#24292e",
    parameter = "#e36209",
    property = "#005cc5",
    operator = "#d73a49",
    punctuation = "#24292e",
    tag = "#22863a",
  },
  ["ayu-dark"] = {
    bg = "#0b0e14",
    fg = "#bfbdb6",
    comment = "#636a72",
    keyword = "#ff8f40",
    string = "#aad94c",
    number = "#d2a6ff",
    constant = "#d2a6ff",
    func = "#ffb454",
    type = "#59c2ff",
    variable = "#bfbdb6",
    parameter = "#d2a6ff",
    property = "#f07178",
    operator = "#f29668",
    punctuation = "#bfbdb6",
    tag = "#39bae6",
  },
  ["ayu-light"] = {
    bg = "#fcfcfc",
    fg = "#5c6166",
    comment = "#adaeb1",
    keyword = "#fa8d3e",
    string = "#86b300",
    number = "#a37acc",
    constant = "#a37acc",
    func = "#f2ae49",
    type = "#399ee6",
    variable = "#5c6166",
    parameter = "#a37acc",
    property = "#f07171",
    operator = "#ed9366",
    punctuation = "#5c6166",
    tag = "#55b4d4",
  },
  dracula = {
    bg = "#282a36",
    fg = "#f8f8f2",
    comment = "#6272a4",
    keyword = "#ff79c6",
    string = "#f1fa8c",
    number = "#bd93f9",
    constant = "#bd93f9",
    func = "#50fa7b",
    type = "#8be9fd",
    variable = "#f8f8f2",
    parameter = "#ffb86c",
    property = "#66d9ef",
    operator = "#ff79c6",
    punctuation = "#f8f8f2",
    tag = "#ff79c6",
  },
  catppuccin = {
    bg = "#1e1e2e",
    fg = "#cdd6f4",
    comment = "#9399b2",
    keyword = "#cba6f7",
    string = "#a6e3a1",
    number = "#fab387",
    constant = "#fab387",
    func = "#89b4fa",
    type = "#f9e2af",
    variable = "#cdd6f4",
    parameter = "#eba0ac",
    property = "#b4befe",
    operator = "#89dceb",
    punctuation = "#9399b2",
    tag = "#89b4fa",
  },
  ["gruvbox-dark"] = {
    bg = "#282828",
    fg = "#ebdbb2",
    comment = "#928374",
    keyword = "#fb4934",
    string = "#b8bb26",
    number = "#d3869b",
    constant = "#d3869b",
    func = "#8ec07c",
    type = "#fabd2f",
    variable = "#83a598",
    parameter = "#ebdbb2",
    property = "#83a598",
    operator = "#fe8019",
    punctuation = "#a89984",
    tag = "#8ec07c",
  },
  ["gruvbox-light"] = {
    bg = "#fbf1c7",
    fg = "#3c3836",
    comment = "#928374",
    keyword = "#9d0006",
    string = "#79740e",
    number = "#8f3f71",
    constant = "#8f3f71",
    func = "#427b58",
    type = "#b57614",
    variable = "#076678",
    parameter = "#3c3836",
    property = "#076678",
    operator = "#af3a03",
    punctuation = "#7c6f64",
    tag = "#427b58",
  },
  tokyonight = {
    bg = "#1a1b26",
    fg = "#c0caf5",
    comment = "#565f89",
    keyword = "#bb9af7",
    string = "#9ece6a",
    number = "#ff9e64",
    constant = "#ff9e64",
    func = "#7aa2f7",
    type = "#2ac3de",
    variable = "#c0caf5",
    parameter = "#e0af68",
    property = "#73daca",
    operator = "#89ddff",
    punctuation = "#89ddff",
    tag = "#f7768e",
  },
}

-- Tree-sitter capture prefixes, most specific first.
local captures = {
  { "comment", "comment" },
  { "variable.parameter", "parameter" },
  { "variable.member", "property" },
  { "property", "property" },
  { "field", "property" },
  { "parameter", "parameter" },
  { "variable.builtin", "constant" },
  { "variable", "variable" },
  { "string.escape", "constant" },
  { "string", "string" },
  { "character", "string" },
  { "number", "number" },
  { "float", "number" },
  { "boolean", "constant" },
  { "constant", "constant" },
  { "function", "func" },
  { "method", "func" },
  { "constructor", "type" },
  { "type", "type" },
  { "module", "type" },
  { "namespace", "type" },
  { "attribute", "type" },
  { "keyword", "keyword" },
  { "conditional", "keyword" },
  { "repeat", "keyword" },
  { "include", "keyword" },
  { "exception", "keyword" },
  { "label", "keyword" },
  { "operator", "operator" },
  { "punctuation", "punctuation" },
  { "tag", "tag" },
}

-- Role of a capture such as "keyword.return", or nil to keep the text color.
---@param capture string Capture name without "@"
---@return MdReadableCodeRole?
function M.role(capture)
  for _, item in ipairs(captures) do
    local prefix = item[1]
    if capture == prefix or capture:sub(1, #prefix + 1) == prefix .. "." then
      return item[2]
    end
  end
end

---@param role MdReadableCodeRole
---@return string
function M.group(role)
  return "MdReadableCodeBlock" .. role:gsub("^%l", string.upper)
end

-- Palette from the preset plus the user's colors; nil when neither is set, in
-- which case code keeps the colorscheme's own syntax highlighting.
---@param opts? MdReadableUserConfigCode
---@return MdReadableCodePalette?
function M.palette(opts)
  opts = opts or {}
  local preset = opts.theme and M.presets[opts.theme]
  if not preset and vim.tbl_isempty(opts.colors or {}) then
    return nil
  end
  return vim.tbl_extend("force", preset or {}, opts.colors or {})
end

---@param color string "#rrggbb"
---@return integer
local function rgb(color)
  return tonumber(color:sub(2), 16)
end
---@param fg integer
---@param bg integer
---@param alpha number Weight of `fg`
---@return integer
local function blend(fg, bg, alpha)
  local function channel(shift)
    local a, b = math.floor(fg / shift) % 256, math.floor(bg / shift) % 256
    return math.floor(a * alpha + b * (1 - alpha) + 0.5)
  end
  return channel(65536) * 65536 + channel(256) * 256 + channel(1)
end

-- Background nudged toward gray so the block stands apart from the page.
---@param base? integer Page background; nil for a transparent page
---@return integer
function M.auto_background(base)
  base = base or (vim.o.background == "light" and 0xffffff or 0x000000)
  return blend(0x808080, base, 0.12)
end

-- Highlight definitions for code blocks.
---@param opts? MdReadableUserConfigCode
---@param base? integer Page background (0xRRGGBB)
---@param fg? integer Default code text color
---@return table<string, vim.api.keyset.highlight>
function M.highlights(opts, base, fg)
  local palette = M.palette(opts) or {}
  local bg = palette.bg and rgb(palette.bg) or M.auto_background(base)
  local text = palette.fg and rgb(palette.fg) or fg
  local label = palette.label or palette.comment
  local result = {
    MdReadableCodeBlock = { fg = text, bg = bg },
    MdReadableCodeBlockLabel = label and { fg = rgb(label), bg = bg } or { link = "Comment" },
  }
  for _, role in ipairs(M.roles) do
    if palette[role] then
      result[M.group(role)] = { fg = rgb(palette[role]) }
    end
  end
  return result
end

-- Error message for invalid `code` options, or nil.
---@param opts MdReadableConfigCode
---@return string?
function M.validate(opts)
  if opts.theme ~= nil and not M.presets[opts.theme] then
    local names = vim.tbl_keys(M.presets)
    table.sort(names)
    return "code.theme must be one of " .. table.concat(names, ", ")
  end
  if opts.label ~= "left" and opts.label ~= "right" then
    return 'code.label must be "left" or "right"'
  end
  if opts.icons ~= nil and opts.icons ~= "mini" and opts.icons ~= "web-devicons" then
    return 'code.icons must be nil, "mini" or "web-devicons"'
  end
  for key, value in pairs(opts.colors or {}) do
    if key ~= "bg" and key ~= "fg" and key ~= "label" and not vim.tbl_contains(M.roles, key) then
      return "code.colors." .. key .. " is not a known color"
    end
    if type(value) ~= "string" or not value:match("^#%x%x%x%x%x%x$") then
      return "code.colors." .. key .. ' must be "#rrggbb"'
    end
  end
end

return M
