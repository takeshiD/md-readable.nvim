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

---@param lines string[] Rendered (display) lines
---@param opts? MdReadableMinimapOptions
---@return MdReadableMinimapRendered
function M.render(lines, opts)
  opts = opts or {}
  local width, height = math.max(1, opts.width or 12), math.max(1, opts.height or 24)
  local ascii = opts.mode == "ascii"
  local vertical = ascii and 1 or 4
  -- Fractional scales fill the minimap exactly; small documents stay 1:1.
  local row_scale = math.min(1, height * vertical / math.max(1, #lines))
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
  local column_scale = math.min(1, width * horizontal / max_width)
  local pixels, display_to_mini, mini_to_display = {}, {}, {}
  for row, occupied in ipairs(chars) do
    local pixel_row = math.floor((row - 1) * row_scale)
    local mini_row = math.floor(pixel_row / vertical) + 1
    display_to_mini[row] = mini_row - 1
    mini_to_display[mini_row] = mini_to_display[mini_row] or row - 1
    pixels[mini_row] = pixels[mini_row] or {}
    for col in pairs(occupied) do
      local pixel_col = math.floor(col * column_scale)
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

-- Headings and code blocks of the reading view, projected onto minimap rows.
-- Several display rows share a minimap row: a heading outranks code, and a
-- higher-level heading outranks a lower one.
---@param rendered MdReadableRendered Reading view
---@param mini MdReadableMinimapRendered
---@return table<integer, string> regions 0-based minimap row to highlight group
function M.regions(rendered, mini)
  local ranks = {}
  ---@param display_row integer 0-based
  ---@param group string
  ---@param rank integer Lower wins
  local function mark(display_row, group, rank)
    local row = mini.display_to_mini[display_row + 1]
    if row and (not ranks[row] or rank < ranks[row].rank) then
      ranks[row] = { group = group, rank = rank }
    end
  end
  for _, h in ipairs(rendered.highlights or {}) do
    local level = h.group:match("^MdReadableHeading(%d)$")
    if level then
      mark(h.row, h.group, tonumber(level) --[[@as integer]])
    end
  end
  for _, block in ipairs(rendered.code_blocks or {}) do
    for row = block.row, block.end_row - 1 do
      mark(row, "MdReadableMinimapCode", 7)
    end
  end
  local regions = {}
  for row, item in pairs(ranks) do
    regions[row] = item.group
  end
  return regions
end

return M
