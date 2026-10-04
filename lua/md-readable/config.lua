local M = {}
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
M.options = vim.deepcopy(M.defaults)
M.options.keymaps = require("md-readable.keymaps").merge(nil, true)
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
function M.get()
  return vim.deepcopy(M.options)
end
return M
