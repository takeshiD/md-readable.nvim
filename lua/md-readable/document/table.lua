local M = {}

-- Byte coordinates refer to the original line, before whitespace trimming.
function M.cells(line)
  local cuts, code, i = {}, nil, 1
  while i <= #line do
    local c = line:sub(i, i)
    if c == "\\" then i = i + 2
    elseif c == "`" then
      local run = line:match("^`+", i)
      if not code then code = #run elseif code == #run then code = nil end
      i = i + #run
    else
      if c == "|" and not code then cuts[#cuts + 1] = i end
      i = i + 1
    end
  end
  if #cuts == 0 then return nil end
  local boundaries = { 0 }
  for _, cut in ipairs(cuts) do boundaries[#boundaries + 1] = cut end
  boundaries[#boundaries + 1] = #line + 1
  local result = {}
  for n = 1, #boundaries - 1 do
    local a, b = boundaries[n] + 1, boundaries[n + 1] - 1
    local raw = line:sub(a, b)
    if not ((n == 1 or n == #boundaries - 1) and raw:match("^%s*$")) then
      local leading = #(raw:match("^%s*") or "")
      local text = raw:match("^%s*(.-)%s*$")
      result[#result + 1] = { text = text, start_col = a - 1 + leading, end_col = a - 1 + leading + #text }
    end
  end
  return result
end

function M.parse(lines, start_row)
  local header, delimiter = M.cells(lines[start_row + 1] or ""), M.cells(lines[start_row + 2] or "")
  if not header or not delimiter or #header ~= #delimiter then return nil end
  local alignments = {}
  for i, cell in ipairs(delimiter) do
    if not cell.text:match("^:?-+:?$") then return nil end
    alignments[i] = cell.text:sub(1, 1) == ":" and (cell.text:sub(-1) == ":" and "center" or "left")
      or (cell.text:sub(-1) == ":" and "right" or "left")
  end
  local rows, row = { { source_row = start_row, cells = header } }, start_row + 2
  while row < #lines do
    local cells = M.cells(lines[row + 1])
    if not cells or lines[row + 1]:match("^%s*$") then break end
    -- GFM ignores excess cells and fills absent trailing cells.
    while #cells > #header do table.remove(cells) end
    while #cells < #header do cells[#cells + 1] = { text = "", start_col = #lines[row + 1], end_col = #lines[row + 1] } end
    rows[#rows + 1] = { source_row = row, cells = cells }
    row = row + 1
  end
  return { type = "table", start_row = start_row, end_row = row, rows = rows, alignments = alignments }
end
return M
