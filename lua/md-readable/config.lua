local M = {}
---@alias MdReadableLayout "integrated"|"separate"|"ondemand"
---@alias MdReadableLinkIcons "unicode"|"ascii"|false|table<MdReadableLinkKind, string>
---@class MdReadableConfigLinks : MdReadableUserConfigLinks
---@field icons MdReadableLinkIcons Markers appended after labelled links
---@class MdReadableConfigNavigation : MdReadableUserConfigNavigation
---@field auto_open boolean Open the navigation panel when a project is detected
---@field width integer Panel width in cells
---@field min_body_width integer
---@class MdReadableConfigTable : MdReadableUserConfigTable
---@field max_cell_width integer
---@class MdReadableConfigFocus : MdReadableUserConfigFocus
---@field coefficient number Dim ratio, 0 (foreground) .. 1 (background)
---@field span integer Extra paragraphs on each side
---@field bop string Vim pattern for the beginning of a paragraph
---@field eop string Vim pattern for the end of a paragraph
---@field priority integer matchadd() priority
---@field color? string Explicit dim colour ("#rrggbb")
---@field cterm_color? integer
---@class MdReadableConfigMinimap : MdReadableUserConfigMinimap
---@field width integer
---@field mode MdReadableMinimapMode
---@field git boolean
---@field diagnostic boolean
---@field severity? vim.diagnostic.SeverityFilter Diagnostics shown in the minimap
---@class MdReadableConfigImages : MdReadableUserConfigImages
---@field enabled boolean
---@field remote boolean Allow downloading remote images
---@field height integer Reserved display rows
---@field max_bytes integer
---@field max_width? integer Display cells; defaults to the reader width
---@field cache_dir? string
---@field cache_ttl? integer Remote cache lifetime in seconds
---@field converter? string Image conversion command
---@field timeout? integer Milliseconds
---@class MdReadableConfigMermaid : MdReadableUserConfigMermaid
---@field command string
---@field enabled? boolean
---@field theme? string
---@field background? string
---@field width? integer Pixels
---@field height? integer Pixels
---@field timeout? integer Milliseconds
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
---@field float MdReadableConfigFloat
---@field adapters MdReadableNavOptions
---@field highlights? table<string, vim.api.keyset.highlight> Highlight group overrides
---@class MdReadableUserConfigLinks
---@field icons? MdReadableLinkIcons
---@class MdReadableUserConfigNavigation
---@field auto_open? boolean
---@field width? integer
---@field min_body_width? integer
---@class MdReadableUserConfigTable
---@field max_cell_width? integer
---@class MdReadableUserConfigFocus
---@field coefficient? number
---@field span? integer
---@field bop? string
---@field eop? string
---@field priority? integer
---@field color? string
---@field cterm_color? integer
---@class MdReadableUserConfigMinimap
---@field width? integer
---@field mode? MdReadableMinimapMode
---@field git? boolean
---@field diagnostic? boolean
---@field severity? vim.diagnostic.SeverityFilter
---@class MdReadableUserConfigImages
---@field enabled? boolean
---@field remote? boolean
---@field height? integer
---@field max_bytes? integer
---@field max_width? integer
---@field cache_dir? string
---@field cache_ttl? integer
---@field converter? string
---@field timeout? integer
---@class MdReadableUserConfigMermaid
---@field command? string
---@field enabled? boolean
---@field theme? string
---@field background? string
---@field width? integer
---@field height? integer
---@field timeout? integer
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
  links = { icons = "unicode" }, -- "unicode", "ascii", false, or { external = "..", ... }
  layout = "integrated",
  navigation = { auto_open = true, width = 28, min_body_width = 48 },
  table = { max_cell_width = 28 },
  focus = { coefficient = 0.5, span = 0, bop = "^\\s*$\\n\\zs", eop = "^\\s*$", priority = 10 },
  minimap = { width = 14, mode = "braille", git = true, diagnostic = true },
  images = { enabled = true, remote = false, height = 10, max_bytes = 20 * 1024 * 1024 },
  mermaid = { command = "mmdc" },
  float = { width = 0.85, height = 0.85, border = "rounded" },
  adapters = {},
}
---@type MdReadableConfig
M.options = vim.deepcopy(M.defaults)
M.options.keymaps = require("md-readable.keymaps").merge(nil, true)
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
  assert(vim.tbl_contains({ "integrated", "separate", "ondemand" }, value.layout), "invalid reader layout")
  assert(type(value.width) == "number" and value.width >= 12, "reader width must be >= 12")
  assert(type(value.debounce) == "number" and value.debounce >= 0, "debounce must be nonnegative")
  assert(value.table.max_cell_width >= 3, "table.max_cell_width must be >= 3")
  assert(value.focus.coefficient >= 0 and value.focus.coefficient <= 1, "focus.coefficient must be between 0 and 1")
  assert(value.float.width > 0 and value.float.width <= 1, "float.width must be a fraction between 0 and 1")
  assert(value.float.height > 0 and value.float.height <= 1, "float.height must be a fraction between 0 and 1")
  assert(value.images.height >= 1, "images.height must be positive")
  M.options = value
  return value
end
---@return MdReadableConfig copy Deep copy of the current options
function M.get()
  return vim.deepcopy(M.options)
end
return M
