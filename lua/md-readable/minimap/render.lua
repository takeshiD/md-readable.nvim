local M = {}
local dots = { { 1, 2, 4, 64 }, { 8, 16, 32, 128 } }

-- Independent of buffers/windows: compress the rendered document, not the source.
---@alias MdReadableMinimapMode "braille"|"ascii"
---@class MdReadableMinimapOptions
---@field width? integer Cells
---@field height? integer Rows
---@field mode? MdReadableMinimapMode
---@field tabstop? integer
---@class MdReadableMinimapRendered
---@field lines string[]
---@field display_to_mini table<integer, integer> 1-based display row to 0-based minimap row
---@field mini_to_display table<integer, integer> 1-based minimap row to 0-based display row
---@class MdReadableMinimapItem Annotation over source rows, published by a provider
---@field start_row integer 0-based source row
---@field end_row integer 0-based, exclusive
---@field kind "add"|"change"|"delete"|"diagnostic"|string
---@field severity? integer vim.diagnostic.severity; lower wins on collisions
---@param lines string[] Rendered (display) lines
---@param opts? MdReadableMinimapOptions
---@return MdReadableMinimapRendered
function M.render(lines, opts)
  opts = opts or {}
  local width, height = math.max(1, opts.width or 12), math.max(1, opts.height or 24)
  local ascii = opts.mode == "ascii"
  local vertical = ascii and 1 or 4
  local row_stride = math.max(1, math.ceil(#lines / (height * vertical)))
  local chars, max_width = {}, 1
  for row, line in ipairs(lines) do
    chars[row] = {}
    local col = 0
    for _, char in ipairs(vim.fn.split(line, "\\zs")) do
      local cells = char == "\t" and ((opts.tabstop or 8) - col % (opts.tabstop or 8)) or vim.fn.strdisplaywidth(char)
      if char ~= "\t" and not char:match("^%s$") then
        for offset = 0, cells - 1 do
          chars[row][col + offset] = true
        end
      end
      col = col + cells
    end
    max_width = math.max(max_width, col)
  end
  local horizontal = ascii and 1 or 2
  local column_stride = math.max(1, math.ceil(max_width / (width * horizontal)))
  local pixels, display_to_mini, mini_to_display = {}, {}, {}
  for row, occupied in ipairs(chars) do
    local pixel_row = math.floor((row - 1) / row_stride)
    local mini_row = math.floor(pixel_row / vertical) + 1
    display_to_mini[row] = mini_row - 1
    mini_to_display[mini_row] = mini_to_display[mini_row] or row - 1
    pixels[mini_row] = pixels[mini_row] or {}
    for col in pairs(occupied) do
      local pixel_col = math.floor(col / column_stride)
      local mini_col = math.floor(pixel_col / horizontal) + 1
      if mini_col <= width then
        local value = ascii and 1 or dots[pixel_col % 2 + 1][pixel_row % 4 + 1]
        pixels[mini_row][mini_col] = bit.bor(pixels[mini_row][mini_col] or 0, value)
      end
    end
  end
  local result = {}
  for row = 1, math.max(1, #mini_to_display) do
    local cells = {}
    for col = 1, width do
      local value = (pixels[row] or {})[col] or 0
      cells[col] = ascii and (value > 0 and "#" or " ") or vim.fn.nr2char(0x2800 + value)
    end
    result[row] = table.concat(cells)
  end
  return { lines = result, display_to_mini = display_to_mini, mini_to_display = mini_to_display }
end

-- Independent provider lanes retain Git and diagnostic information on collisions.
---@param items? MdReadableMinimapItem[]
---@param map MdReadableSourceMap
---@param rendered MdReadableMinimapRendered
---@return table<integer, MdReadableMinimapItem> projected 0-based minimap row to item
function M.annotations(items, map, rendered)
  local projected = {}
  for _, item in ipairs(items or {}) do
    local first = math.max(0, item.start_row or 0)
    local last = math.max(first, (item.end_row or first + 1) - 1)
    local first_display = map:to_display(first, 0)
    local last_display = map:to_display(last, 2147483647)
    local top = rendered.display_to_mini[first_display + 1] or 0
    local bottom = rendered.display_to_mini[last_display + 1] or (#rendered.lines - 1)
    for row = math.min(top, bottom), math.max(top, bottom) do
      local old = projected[row]
      if not old or (item.severity or 99) < (old.severity or 99) then
        projected[row] = item
      end
    end
  end
  return projected
end

return M
