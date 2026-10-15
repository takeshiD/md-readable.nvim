local M = {}
---@alias MdReadableLayout "integrated"|"separate"|"ondemand"
---@alias MdReadableLinkIcons "unicode"|"ascii"|false|table<MdReadableLinkKind, string>
---@class MdReadableConfigLinks : MdReadableUserConfigLinks
---@field enable boolean false shows link labels as plain text without kind markers
---@field icons MdReadableLinkIcons Markers appended after labelled links
---@class MdReadableConfigNavigation : MdReadableUserConfigNavigation
---@field enable boolean Open the book tree with the reading view when a project is detected
---@field width integer Panel width in cells
---@field min_body_width integer
---@field follow boolean Moving over a heading in a panel scrolls the reading view
---@field style "auto"|"sidebar"|"float" How toggle_nav opens the book tree; auto: by width and layout
---@field fold MdReadableConfigNavigationFold
---@alias MdReadableNavKeys string|string[]|false One key, a list, or false (none)
---@class MdReadableConfigNavigationFold
---@field keys table<MdReadableNavFoldAction, MdReadableNavKeys>
---@field icons {collapsed:string, expanded:string, leaf:string, current:string}
---@class MdReadableConfigTable : MdReadableUserConfigTable
---@field enable boolean false shows tables as their Markdown source
---@field max_cell_width integer
---@class MdReadableConfigFocus : MdReadableUserConfigFocus
---@field enable boolean Start Focus mode when a reading view opens
---@field coefficient number Dim ratio, 0 (foreground) .. 1 (background)
---@field span integer Extra paragraphs on each side
---@field bop string Vim pattern for the beginning of a paragraph
---@field eop string Vim pattern for the end of a paragraph
---@field priority integer matchadd() priority
---@field color? string Explicit dim colour ("#rrggbb")
---@field cterm_color? integer
---@class MdReadableConfigMinimap : MdReadableUserConfigMinimap
---@field enable boolean Open the minimap when a reading view opens
---@field follow boolean Moving in the minimap scrolls the reading view
---@field width integer
---@field mode MdReadableMinimapMode
---@class MdReadableConfigImages : MdReadableUserConfigImages
---@field enable boolean
---@field remote boolean Allow downloading remote images
---@field width? integer Columns the image box always takes (nil: the body width)
---@field height? integer Rows the image box always takes (nil: the reading window height)
---@field min_width? integer
---@field max_width? integer Display cells; defaults to the reader width
---@field min_height? integer
---@field max_height? integer
---@field max_bytes integer
---@field cache_dir? string
---@field cache_ttl? integer Remote cache lifetime in seconds
---@field converter? string Image conversion command
---@field timeout? integer Milliseconds
---@class MdReadableMermaidMmdcOpts
---@field no_sandbox? boolean Start mmdc's Chromium with --no-sandbox
---@field theme? string mmdc --theme (default "default")
---@field background? string mmdc --backgroundColor (default "transparent")
---@field width? integer Page width in pixels (default 1600)
---@field height? integer Page height in pixels (default 1000)
---@class MdReadableMermaidTermaidOpts
---@field ascii? boolean --ascii
---@field sharp_edges? boolean --sharp-edges
---@field inline_edge_labels? boolean --inline-edge-labels
---@field gap? integer --gap
---@field padding_x? integer --padding-x
---@field padding_y? integer --padding-y
---@class MdReadableConfigMermaid : MdReadableUserConfigMermaid
---@field enable boolean
---@field renderer "mmdc"|"termaid" mmdc draws images; termaid draws Unicode text (any terminal)
---@field command? string Renderer command, may include arguments ("uvx termaid"); default: the renderer's name
---@field args string[] Extra arguments for the renderer
---@field scale number mmdc --scale; higher keeps enlarged diagrams sharp
---@field max_rows integer Upper bound of the rows a diagram fills
---@field mmdc_opts MdReadableMermaidMmdcOpts
---@field termaid_opts MdReadableMermaidTermaidOpts
---@field timeout? integer Milliseconds
---@class MdReadableConfigCode : MdReadableUserConfigCode
---@field theme? string Syntax palette preset (see md-readable.ui.code_theme); nil keeps the colorscheme
---@field colors table<string, string> "#rrggbb" per role, bg, fg or label; overrides the preset
---@field label "left"|"right" Corner of the icon and language name
---@field icons? "mini"|"web-devicons" Language icon provider; nil shows no icon
---@class MdReadableConfigWatch : MdReadableUserConfigWatch
---@field enable boolean Reload the source when its file changes outside Neovim
---@class MdReadableGitSign
---@field text string 1-2 cells in the sign column
---@field color? string "#rrggbb" or a highlight group name; nil uses the default group
---@class MdReadableUserGitSign
---@field text? string
---@field color? string
---@class MdReadableConfigGitSigns : MdReadableUserConfigGitSigns
---@field add MdReadableGitSign
---@field change MdReadableGitSign
---@field delete MdReadableGitSign
---@class MdReadableUserConfigGitSigns
---@field add? MdReadableUserGitSign
---@field change? MdReadableUserGitSign
---@field delete? MdReadableUserGitSign
---@class MdReadableConfigGit : MdReadableUserConfigGit
---@field enable boolean Git status of the source in the reading sign column
---@field signs MdReadableConfigGitSigns
---@class MdReadableConfigFloat : MdReadableUserConfigFloat
---@field width number Fraction of the editor width (0, 1]
---@field height number Fraction of the editor height (0, 1]
---@field border string|string[]
---@class MdReadableConfig
---@field width integer Body width in cells
---@field debounce integer Refresh delay in milliseconds
---@field keymaps table<string, MdReadableKeymapSpec> Resolved reading-buffer keymaps
---@field use_default_keymaps boolean
---@field theme string "default", "dark", "light"
---@field heading_rules boolean
---@field center boolean
---@field links MdReadableConfigLinks
---@field layout MdReadableLayout
---@field navigation MdReadableConfigNavigation
---@field table MdReadableConfigTable
---@field focus MdReadableConfigFocus
---@field minimap MdReadableConfigMinimap
---@field images MdReadableConfigImages
---@field mermaid MdReadableConfigMermaid
---@field code MdReadableConfigCode
---@field alerts MdReadableConfigAlerts
---@field watch MdReadableConfigWatch
---@field git MdReadableConfigGit
---@field float MdReadableConfigFloat
---@field adapters MdReadableNavOptions
---@field highlights? table<string, vim.api.keyset.highlight> Highlight group overrides
---@class MdReadableUserConfigLinks
---@field enable? boolean
---@field icons? MdReadableLinkIcons
---@class MdReadableUserConfigNavigation
---@field enable? boolean
---@field auto_open? boolean Former name of `enable`
---@field follow? boolean
---@field style? "auto"|"sidebar"|"float"
---@field fold? {keys?: table<MdReadableNavFoldAction, MdReadableNavKeys>, icons?: {collapsed?:string, expanded?:string, leaf?:string, current?:string}}
---@field width? integer
---@field min_body_width? integer
---@class MdReadableUserConfigTable
---@field enable? boolean
---@field max_cell_width? integer
---@class MdReadableUserConfigFocus
---@field enable? boolean
---@field coefficient? number
---@field span? integer
---@field bop? string
---@field eop? string
---@field priority? integer
---@field color? string
---@field cterm_color? integer
---@class MdReadableUserConfigMinimap
---@field enable? boolean
---@field follow? boolean
---@field width? integer
---@field mode? MdReadableMinimapMode
---@class MdReadableUserConfigImages
---@field enable? boolean
---@field enabled? boolean Deprecated name of `enable`
---@field remote? boolean
---@field width? integer
---@field height? integer
---@field min_width? integer
---@field max_width? integer
---@field min_height? integer
---@field max_height? integer
---@field max_bytes? integer
---@field cache_dir? string
---@field cache_ttl? integer
---@field converter? string
---@field timeout? integer
---@class MdReadableUserConfigMermaid
---@field enable? boolean
---@field enabled? boolean Deprecated name of `enable`
---@field renderer? "mmdc"|"termaid"
---@field command? string
---@field args? string[]
---@field scale? number
---@field max_rows? integer
---@field mmdc_opts? MdReadableMermaidMmdcOpts
---@field termaid_opts? MdReadableMermaidTermaidOpts
---@field timeout? integer
---@class MdReadableUserConfigCode
---@field theme? string
---@field colors? table<string, string>
---@field label? "left"|"right"
---@field icons? "mini"|"web-devicons"
---@class MdReadableUserConfigAlerts
---@field enable? boolean
---@field icons? MdReadableAlertIcons
---@field kinds? table<string, MdReadableAlertKind>
---@field aliases? table<string, string>
---@class MdReadableUserConfigWatch
---@field enable? boolean
---@class MdReadableUserConfigGit
---@field enable? boolean
---@field signs? MdReadableUserConfigGitSigns
---@class MdReadableUserConfigFloat
---@field width? number
---@field height? number
---@field border? string|string[]
---@class MdReadableUserConfig
---@field width? integer
---@field debounce? integer
---@field keymaps? boolean|table<string, MdReadableKeymapSpec> false installs none, true keeps the defaults
---@field use_default_keymaps? boolean
---@field theme? string
---@field heading_rules? boolean
---@field center? boolean
---@field links? MdReadableUserConfigLinks
---@field layout? MdReadableLayout
---@field navigation? MdReadableUserConfigNavigation
---@field table? MdReadableUserConfigTable
---@field focus? MdReadableUserConfigFocus
---@field minimap? MdReadableUserConfigMinimap
---@field images? MdReadableUserConfigImages
---@field mermaid? MdReadableUserConfigMermaid
---@field code? MdReadableUserConfigCode
---@field alerts? MdReadableUserConfigAlerts
---@field watch? MdReadableUserConfigWatch
---@field git? MdReadableUserConfigGit
---@field float? MdReadableUserConfigFloat
---@field adapters? MdReadableNavOptions
---@field highlights? table<string, vim.api.keyset.highlight>
---@type MdReadableConfig
M.defaults = {
  width = 100,
  debounce = 100,
  -- Reading-buffer keymaps, merged with require("md-readable.keymaps").defaults.
  keymaps = {},
  use_default_keymaps = true,
  theme = "default",
  heading_rules = true,
  center = true,
  links = { enable = true, icons = "unicode" }, -- "unicode", "ascii", false, or { external = "..", ... }
  layout = "integrated",
  navigation = {
    enable = true,
    follow = true,
    style = "auto",
    width = 28,
    min_body_width = 48,
    fold = {
      keys = {
        collapse = { "h", "<Left>" },
        expand = { "l", "<Right>" },
        toggle = "za",
        collapse_recursive = "zC",
        expand_recursive = "zO",
        collapse_all = "zM",
        expand_all = "zR",
      },
      icons = { collapsed = "+ ", expanded = "- ", leaf = "  ", current = "> " },
    },
  },
  table = { enable = true, max_cell_width = 28 },
  focus = { enable = true, coefficient = 0.5, span = 0, bop = "^\\s*$\\n\\zs", eop = "^\\s*$", priority = 10 },
  minimap = { enable = true, follow = true, width = 12, mode = "braille" },
  -- Image box as in snacks.image: width/height fix it, min/max bound it; the
  -- image keeps its aspect ratio and is not enlarged past its own size.
  images = { enable = true, remote = false, max_height = 40, max_bytes = 20 * 1024 * 1024 },
  mermaid = {
    enable = true,
    renderer = "mmdc",
    -- command = nil: "mmdc" or "termaid" after the renderer
    args = {},
    scale = 3,
    max_rows = 40,
    mmdc_opts = { no_sandbox = false },
    termaid_opts = {},
  },
  code = { label = "left", colors = {} },
  alerts = vim.deepcopy(require("md-readable.ui.alerts").defaults),
  watch = { enable = true },
  git = {
    enable = true,
    signs = { add = { text = "▎" }, change = { text = "▎" }, delete = { text = "▁" } },
  },
  float = { width = 0.85, height = 0.85, border = "rounded" },
  adapters = {},
}
---@type MdReadableConfig
M.options = vim.deepcopy(M.defaults)
M.options.keymaps = require("md-readable.keymaps").merge(nil, true)
-- Moves the former `enabled` key of images and mermaid to `enable` in place.
-- An explicit `enable` in `given` (the options as written) wins.
---@generic T: table
---@param value T
---@param given? table Defaults to `value`
---@return T value
function M.normalize(value, given)
  given = given or value
  for _, name in ipairs({ "images", "mermaid" }) do
    local section, written = value[name], given[name]
    if type(section) == "table" then
      if type(written) == "table" and written.enable == nil and written.enabled ~= nil then
        section.enable = written.enabled
      end
      section.enabled = nil
    end
  end
  -- navigation.auto_open is the former name of navigation.enable.
  local navigation, written = rawget(value, "navigation"), rawget(given, "navigation")
  if type(navigation) == "table" then
    if type(written) == "table" and written.enable == nil and written.auto_open ~= nil then
      navigation.enable = written.auto_open
    end
    navigation.auto_open = nil
  end
  return value
end
---@param opts? MdReadableUserConfig
---@return MdReadableConfig
function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "md-readable.setup expects a table")
  opts = opts or {}
  local keymaps = opts.keymaps
  assert(
    keymaps == nil or type(keymaps) == "boolean" or type(keymaps) == "table",
    "keymaps must be a table, true or false"
  )
  -- keymaps are merged per key, not deeply, so a user entry replaces the default.
  local value = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), vim.tbl_extend("force", opts, { keymaps = {} }))
  if keymaps == true then
    keymaps = nil
  end
  value.keymaps = require("md-readable.keymaps").merge(keymaps, value.use_default_keymaps)
  -- A key list replaces the default list of that action instead of merging
  -- index by index ({ "za" } over { "h", "<Left>" } must not keep "<Left>").
  local fold_keys = ((opts.navigation or {}).fold or {}).keys
  if type(fold_keys) == "table" then
    for action, keys in pairs(fold_keys) do
      value.navigation.fold.keys[action] = type(keys) == "table" and vim.deepcopy(keys) or keys
    end
  end
  M.normalize(value, opts)
  for _, name in ipairs({
    "links",
    "table",
    "focus",
    "minimap",
    "images",
    "mermaid",
    "watch",
    "git",
    "navigation",
    "alerts",
  }) do
    assert(type(value[name].enable) == "boolean", name .. ".enable must be true or false")
  end
  assert(vim.tbl_contains({ "integrated", "separate", "ondemand" }, value.layout), "invalid reader layout")
  assert(type(value.width) == "number" and value.width >= 12, "reader width must be >= 12")
  assert(type(value.debounce) == "number" and value.debounce >= 0, "debounce must be nonnegative")
  assert(value.table.max_cell_width >= 3, "table.max_cell_width must be >= 3")
  assert(value.focus.coefficient >= 0 and value.focus.coefficient <= 1, "focus.coefficient must be between 0 and 1")
  assert(value.float.width > 0 and value.float.width <= 1, "float.width must be a fraction between 0 and 1")
  assert(value.float.height > 0 and value.float.height <= 1, "float.height must be a fraction between 0 and 1")
  local alerts_err = require("md-readable.ui.alerts").validate(value.alerts)
  assert(not alerts_err, alerts_err)
  for _, key in ipairs({ "width", "height", "min_width", "max_width", "min_height", "max_height" }) do
    local size = value.images[key]
    assert(size == nil or (type(size) == "number" and size >= 1), "images." .. key .. " must be a positive number")
  end
  assert(
    vim.tbl_contains({ "mmdc", "termaid" }, value.mermaid.renderer),
    'mermaid.renderer must be "mmdc" or "termaid"'
  )
  local mermaid = value.mermaid
  assert(
    mermaid.command == nil or (type(mermaid.command) == "string" and vim.trim(mermaid.command) ~= ""),
    'mermaid.command must be a command such as "mmdc" or "uvx termaid"'
  )
  assert(vim.islist(mermaid.args), "mermaid.args must be a list of strings")
  for _, arg in ipairs(mermaid.args) do
    assert(type(arg) == "string", "mermaid.args must be a list of strings")
  end
  assert(type(mermaid.mmdc_opts) == "table", "mermaid.mmdc_opts must be a table")
  assert(type(mermaid.termaid_opts) == "table", "mermaid.termaid_opts must be a table")
  for name in pairs(mermaid.termaid_opts) do
    assert(
      require("md-readable.providers.termaid").flags[name],
      "mermaid.termaid_opts." .. name .. " is not a termaid option"
    )
  end
  assert(
    vim.tbl_contains({ "auto", "sidebar", "float" }, value.navigation.style),
    'navigation.style must be "auto", "sidebar" or "float"'
  )
  for action, keys in pairs(value.navigation.fold.keys) do
    local list = type(keys) == "table" and keys or { keys }
    for _, lhs in ipairs(keys == false and {} or list) do
      assert(type(lhs) == "string" and lhs ~= "", "navigation.fold.keys." .. action .. " must be keys or false")
    end
  end
  for name, icon in pairs(value.navigation.fold.icons) do
    assert(type(icon) == "string", "navigation.fold.icons." .. name .. " must be a string")
  end
  local code_err = require("md-readable.ui.code_theme").validate(value.code)
  assert(not code_err, code_err)
  for kind, sign in pairs(value.git.signs) do
    local width = type(sign.text) == "string" and vim.fn.strdisplaywidth(sign.text) or 0
    assert(width >= 1 and width <= 2, "git.signs." .. kind .. ".text must be 1 or 2 cells wide")
    assert(sign.color == nil or type(sign.color) == "string", "git.signs." .. kind .. ".color must be a string")
  end
  M.options = value
  return value
end
---@return MdReadableConfig copy Deep copy of the current options
function M.get()
  return vim.deepcopy(M.options)
end
return M
