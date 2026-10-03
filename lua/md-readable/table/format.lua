local M = {}

-- Preserve the Markdown spelling (escapes, inline code and tabs) while measuring
-- padding in terminal cells. A tab's width depends on the preceding columns.
local function padded(text, width, alignment, column)
  local used = vim.fn.strdisplaywidth(text, column)
  local left = alignment == "right" and math.max(0, width - used)
    or alignment == "center" and math.floor(math.max(0, width - used) / 2)
    or 0
  -- Tabs may change width after left padding. Find a padding that still fits.
  while left > 0 and left + vim.fn.strdisplaywidth(text, column + left) > width do
    left = left - 1
  end
  local right = math.max(0, width - left - vim.fn.strdisplaywidth(text, column + left))
  return string.rep(" ", left) .. text .. string.rep(" ", right)
end

function M.format(tbl)
  local columns = #(tbl.alignments or {})
  for _, row in ipairs(tbl.rows) do
    columns = math.max(columns, #row.cells)
  end
  if columns == 0 or #tbl.rows == 0 then
    return {}
  end
  local prefix = tbl.prefix or ""
  local base = vim.fn.strdisplaywidth(prefix) + 2
  local widths, start = {}, base
  for col = 1, columns do
    local width = 3
    for _, row in ipairs(tbl.rows) do
      width = math.max(width, vim.fn.strdisplaywidth((row.cells[col] or {}).text or "", start))
    end
    widths[col], start = width, start + width + 3
  end
  local lines = {}
  for index, row in ipairs(tbl.rows) do
    local cells, column = {}, base
    for col = 1, columns do
      cells[col] = padded((row.cells[col] or {}).text or "", widths[col], (tbl.alignments or {})[col], column)
      column = column + widths[col] + 3
    end
    lines[#lines + 1] = prefix .. "| " .. table.concat(cells, " | ") .. " |"
    if index == 1 then
      local rules = {}
      for col = 1, columns do
        local align, width = (tbl.alignments or {})[col], widths[col]
        if align == "center" then
          rules[col] = ":" .. string.rep("-", width - 2) .. ":"
        elseif align == "right" then
          rules[col] = string.rep("-", width - 1) .. ":"
        elseif align == "left" then
          rules[col] = ":" .. string.rep("-", width - 1)
        else
          rules[col] = string.rep("-", width)
        end
      end
      lines[#lines + 1] = prefix .. "| " .. table.concat(rules, " | ") .. " |"
    end
  end
  return lines
end

return M
