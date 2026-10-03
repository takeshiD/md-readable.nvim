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
  local function contextual_cells(line)
    local prefix = line:match("^%s*") or ""
    local depth = 0
    while line:sub(#prefix + 1, #prefix + 1) == ">" do
      local marker = line:sub(#prefix + 1):match("^>%s*")
      prefix, depth = prefix .. marker, depth + 1
    end
    local cells = M.cells(line:sub(#prefix + 1))
    for _, cell in ipairs(cells or {}) do
      cell.start_col, cell.end_col = cell.start_col + #prefix, cell.end_col + #prefix
    end
    return cells, prefix, depth
  end
  local header, prefix, depth = contextual_cells(lines[start_row + 1] or "")
  local delimiter, _, delimiter_depth = contextual_cells(lines[start_row + 2] or "")
  if depth ~= delimiter_depth then return nil end
  if not header or not delimiter or #header ~= #delimiter then return nil end
  local alignments = {}
  for i, cell in ipairs(delimiter) do
    if not cell.text:match("^:?-+:?$") then return nil end
    alignments[i] = cell.text:sub(1, 1) == ":" and (cell.text:sub(-1) == ":" and "center" or "left")
      or (cell.text:sub(-1) == ":" and "right" or "left")
  end
  local rows, row = { { source_row = start_row, cells = header } }, start_row + 2
  while row < #lines do
    local cells, _, row_depth = contextual_cells(lines[row + 1])
    if not cells or row_depth ~= depth or lines[row + 1]:match("^%s*$") then break end
    -- GFM ignores excess cells and fills absent trailing cells.
    while #cells > #header do table.remove(cells) end
    while #cells < #header do cells[#cells + 1] = { text = "", start_col = #lines[row + 1], end_col = #lines[row + 1] } end
    rows[#rows + 1] = { source_row = row, cells = cells }
    row = row + 1
  end
  -- The formatter prefixes every output row with this exact container spelling;
  -- cell coordinates remain absolute byte offsets in the original source line.
  return { type = "table", start_row = start_row, end_row = row, rows = rows, alignments = alignments, prefix = prefix }
end
return M
