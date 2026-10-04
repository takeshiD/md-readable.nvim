-- Buffer-local keymaps of reading buffers. A spec is an action name, a
-- function, false, or { action_or_function, mode = ..., desc = ..., <map opts> }.
local M = {}
M.defaults = {
  ["q"] = "actions.close",
  ["<CR>"] = "actions.open",
  ["g?"] = "actions.show_help",
  ["gs"] = "actions.source",
  ["]]"] = "actions.heading_next",
  ["[["] = "actions.heading_prev",
  ["]p"] = "actions.next_page",
  ["[p"] = "actions.prev_page",
  ["gn"] = "actions.toggle_nav",
  ["gO"] = "actions.outline",
  ["gl"] = "actions.links",
  ["g/"] = "actions.search",
  ["gz"] = { "actions.toggle_focus", mode = { "n", "x" } },
  ["go"] = "actions.toggle_minimap",
  ["za"] = "actions.expand",
}
local reserved = { mode = true, desc = true, callback = true, buffer = true }

-- Returns { lhs, mode, callback, desc, opts } or nil plus an error message.
function M.resolve(lhs, spec)
  if spec == false then
    return nil
  end
  local entry = type(spec) == "table" and spec or { spec }
  local target = entry.callback or entry[1]
  local action, name, desc
  if type(target) == "string" then
    action, name = require("md-readable.actions").get(target)
    if not action then
      return nil, string.format("keymaps[%q]: unknown action %q", lhs, target)
    end
    target, desc = action.callback, action.desc
  end
  if type(target) ~= "function" then
    return nil, string.format("keymaps[%q]: expected an action name, a function or false", lhs)
  end
  local opts = {}
  for key, value in pairs(entry) do
    if type(key) == "string" and not reserved[key] then
      opts[key] = value
    end
  end
  return {
    lhs = lhs,
    mode = entry.mode or "n",
    callback = target,
    desc = entry.desc or desc or "md-readable",
    action = name,
    opts = opts,
  }
end

-- Combines defaults with the user's table. false/nil disables a key.
function M.merge(user, use_defaults)
  local result = {}
  if user == false then
    return result
  end
  if use_defaults ~= false then
    for lhs, spec in pairs(M.defaults) do
      result[lhs] = vim.deepcopy(spec)
    end
  end
  if type(user) == "table" then
    for lhs, spec in pairs(user) do
      result[lhs] = spec
    end
  end
  for lhs, spec in pairs(result) do
    local resolved, err = M.resolve(lhs, spec)
    if not resolved and err then
      error(err, 0)
    end
    if not resolved then
      result[lhs] = nil
    end
  end
  return result
end

function M.attach(buf, keymaps)
  for lhs, spec in pairs(keymaps or {}) do
    local map = M.resolve(lhs, spec)
    if map then
      local opts = vim.tbl_extend("force", { silent = true }, map.opts, { buffer = buf, desc = map.desc })
      vim.keymap.set(map.mode, lhs, map.callback, opts)
    end
  end
end

function M.list(keymaps)
  local items = {}
  for lhs, spec in pairs(keymaps or {}) do
    local map = M.resolve(lhs, spec)
    if map then
      local mode = type(map.mode) == "table" and table.concat(map.mode, ",") or map.mode
      items[#items + 1] = { lhs = lhs, mode = mode, desc = map.desc }
    end
  end
  for _, item in ipairs({
    { lhs = "y / Y", mode = "n,x", desc = "Copy Markdown source" },
    { lhs = "/ ? n N", mode = "n", desc = "Search displayed text" },
    { lhs = "<C-o> / <C-i>", mode = "n", desc = "Source jumplist" },
  }) do
    items[#items + 1] = item
  end
  table.sort(items, function(a, b)
    return a.desc:lower() < b.desc:lower()
  end)
  return items
end

function M.help()
  local s = require("md-readable.reader.session").current()
  local items = M.list(s and s.config.keymaps or require("md-readable.config").get().keymaps)
  local lhs_width, mode_width = 0, 0
  for _, item in ipairs(items) do
    lhs_width = math.max(lhs_width, vim.fn.strdisplaywidth(item.lhs))
    mode_width = math.max(mode_width, #item.mode)
  end
  local lines, width = {}, 0
  for _, item in ipairs(items) do
    local line = string.format(
      " %s%s  %s%s  %s",
      item.lhs,
      string.rep(" ", lhs_width - vim.fn.strdisplaywidth(item.lhs)),
      item.mode,
      string.rep(" ", mode_width - #item.mode),
      item.desc
    )
    lines[#lines + 1] = line
    width = math.max(width, vim.fn.strdisplaywidth(line) + 1)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable, vim.bo[buf].bufhidden = false, "wipe"
  width = math.min(width, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = " md-readable keymaps ",
    title_pos = "center",
  })
  for _, key in ipairs({ "q", "<Esc>", "g?" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true })
  end
  return win, buf
end
return M
