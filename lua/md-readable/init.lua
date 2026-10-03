local M = {}
local commands = {
  "vert",
  "float",
  "source",
  "close",
  "refresh",
  "nav",
  "outline",
  "prev",
  "next",
  "heading-prev",
  "heading-next",
  "links",
  "open",
  "search",
  "focus",
  "theme",
  "minimap",
  "table",
  "expand",
  "tab",
  "images",
  "diagnostics",
  "select",
}
local function session()
  local s = require("md-readable.reader.session").current()
  if not s then
    error("Open a reading view with :MdReadable first")
  end
  return s
end
function M.setup(opts)
  require("md-readable.config").setup(opts)
  require("md-readable.ui.theme").setup()
end
function M.open(mode)
  return require("md-readable.reader.session").open(mode)
end
local function source_position(s)
  if
    vim.api.nvim_get_current_win() == s.source_win
    and s.source_win ~= s.read_win
    and vim.api.nvim_win_get_buf(s.source_win) == s.source_buf
  then
    local pos = vim.api.nvim_win_get_cursor(s.source_win)
    return pos[1] - 1, pos[2]
  end
  local pos = vim.api.nvim_win_get_cursor(s.read_win)
  return s.map:to_source(pos[1] - 1, pos[2])
end
local function edit_table(s, action, count)
  local row, col = source_position(s)
  for _, tbl in ipairs(s.document.tables or {}) do
    if row >= tbl.start_row and row < tbl.end_row then
      local lines, err
      if action == "format" then
        lines = require("md-readable.table.format").format(tbl)
      else
        local index = 1
        if action:match("^row_") then
          for i, item in ipairs(tbl.rows) do
            if item.source_row <= row then
              index = i - 1
            end
          end
        else
          for _, item in ipairs(tbl.rows) do
            if item.source_row == row then
              for i, cell in ipairs(item.cells) do
                if cell.start_col <= col then
                  index = i
                end
              end
            end
          end
        end
        lines, err = require("md-readable.table.edit").edit(tbl, action, index, count or 1)
      end
      if not lines then
        error(err or "Cannot edit this table")
      end
      local before = vim.api.nvim_buf_get_lines(s.source_buf, tbl.start_row, tbl.end_row, false)
      if not vim.deep_equal(before, lines) then
        if not vim.bo[s.source_buf].modifiable then
          error("Source buffer is not modifiable")
        end
        vim.api.nvim_buf_set_lines(s.source_buf, tbl.start_row, tbl.end_row, false, lines)
        s:refresh()
        s:jump_source(row, col)
      end
      return
    end
  end
  error("Cursor is not in a Markdown table")
end
function M.action(command, args, opts)
  args, opts = args or {}, opts or {}
  if not command or command == "" then
    return M.open("current")
  end
  if command == "vert" or command == "float" then
    return M.open(command)
  end
  if command == "close" then
    return require("md-readable.reader.session").close()
  end
  if command == "source" then
    return require("md-readable.reader.session").source()
  end
  local s = session()
  if command == "refresh" then
    s:load_navigation()
    s:refresh()
  elseif command == "nav" then
    require("md-readable.ui.navigation").toggle(s)
  elseif command == "outline" then
    require("md-readable.ui.navigation").outline(s)
  elseif command == "prev" or command == "next" then
    require("md-readable.ui.navigation").move(s, command)
  elseif command == "select" then
    require("md-readable.ui.navigation").select(s)
  elseif command == "heading-prev" or command == "heading-next" then
    local row = source_position(s)
    local found
    for _, heading in ipairs(s.document.headings or {}) do
      local at = heading.range.start.row
      if command == "heading-next" and at > row then
        found = heading
        break
      end
      if command == "heading-prev" and at < row then
        found = heading
      end
    end
    if found then
      s:jump_source(found.range.start.row, 0)
    end
  elseif command == "links" then
    require("md-readable.ui.links").open(s)
  elseif command == "open" then
    local row, col = source_position(s)
    for _, control in ipairs(s.rendered.controls or {}) do
      if control.row == vim.api.nvim_win_get_cursor(s.read_win)[1] - 1 then
        if control.kind == "tabs" then
          s.tabs[control.source_row] = (s.tabs[control.source_row] or 1) % #control.labels + 1
        else
          s.expanded[control.source_row] = not s.expanded[control.source_row]
        end
        s:refresh()
        return
      end
    end
    for _, link in ipairs(s.document.links or {}) do
      local r = link.range
      if row == r.start.row and col >= r.start.byteColumn and col <= r["end"].byteColumn then
        return require("md-readable.ui.links").follow(s, link)
      end
    end
    require("md-readable.ui.cell").open(s)
  elseif command == "search" then
    require("md-readable.reader.search").open(s, #args > 0 and table.concat(args, " ") or nil)
  elseif command == "focus" then
    local enabled = args[1] == "on" or (args[1] ~= "off" and not s.focus_enabled)
    s.focus_enabled = enabled
    local range = opts.range and opts.range > 0 and { start_row = opts.line1 - 1, end_row = opts.line2 } or nil
    require("md-readable.reader.focus").set(s, enabled, range)
  elseif command == "theme" then
    local name = args[1] or "default"
    local applied, err = require("md-readable.ui.theme").apply(s.read_win, name, s.config)
    if not applied then
      error(err)
    end
    s.config.theme = name
    require("md-readable.reader.focus").update(s)
  elseif command == "minimap" then
    local map = require("md-readable.nav.minimap")
    local action = ({ on = "open", off = "close", focus = "focus", toggle = "toggle" })[args[1] or "toggle"]
    if not action then
      error("minimap: on | off | toggle | focus")
    end
    map[action](s)
  elseif command == "table" then
    local action = (args[1] or "format"):gsub("-", "_")
    if
      not vim.tbl_contains(
        { "format", "row_before", "row_after", "row_delete", "col_before", "col_after", "col_delete" },
        action
      )
    then
      error("table: format | row-before | row-after | row-delete | col-before | col-after | col-delete [count]")
    end
    edit_table(s, action, tonumber(args[2]) or 1)
  elseif command == "expand" then
    local row = source_position(s)
    s.expanded[row] = not s.expanded[row]
    s:refresh()
  elseif command == "tab" then
    local row = source_position(s)
    for _, control in ipairs(s.rendered.controls or {}) do
      if control.kind == "tabs" and control.source_row <= row then
        s.tabs[control.source_row] = tonumber(args[1]) or ((s.tabs[control.source_row] or 1) % #control.labels + 1)
      end
    end
    s:refresh()
  elseif command == "images" then
    if args[1] ~= "allow" and args[1] ~= "deny" then
      error("images: allow | deny")
    end
    s.config.images.remote = args[1] == "allow"
    require("md-readable.providers.image").update(s)
  elseif command == "diagnostics" then
    local items = {}
    for _, d in ipairs((s.nav_result and s.nav_result.diagnostics) or (s.snapshot and s.snapshot.diagnostics) or {}) do
      items[#items + 1] =
        { text = (d.code or "") .. " " .. (d.message or tostring(d)), type = d.severity == "error" and "E" or "W" }
    end
    for index, message in pairs(require("md-readable.providers.image").errors(s)) do
      items[#items + 1] = { text = "image " .. index .. ": " .. tostring(message), type = "W" }
    end
    if #items == 0 then
      vim.notify("md-readable: no navigation diagnostics")
    else
      vim.fn.setqflist({}, " ", { title = "md-readable diagnostics", items = items })
      vim.cmd("copen")
    end
  else
    error("Unknown MdReadable command: " .. command)
  end
end
function M.command(opts)
  local args = vim.deepcopy(opts.fargs)
  local command = table.remove(args, 1)
  local ok, err = pcall(M.action, command, args, opts)
  if not ok then
    vim.notify("md-readable: " .. tostring(err), vim.log.levels.ERROR)
  end
end
function M.complete(lead)
  return vim.tbl_filter(function(c)
    return c:sub(1, #lead) == lead
  end, commands)
end
return M
