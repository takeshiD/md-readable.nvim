local M = {}
local inline = require("md-readable.renderers.inline")
local function display(pieces)
  local text = {}
  for _, item in ipairs(pieces) do
    text[#text + 1] = item.text
  end
  return table.concat(text)
end
local function clipped(pieces, width, cell)
  if vim.fn.strdisplaywidth(display(pieces)) <= width then
    return pieces, false
  end
  local result, used = {}, 0
  for _, item in ipairs(pieces) do
    local part = ""
    for index = 0, vim.fn.strchars(item.text, true) - 1 do
      local char = vim.fn.strcharpart(item.text, index, 1, true)
      local size = vim.fn.strdisplaywidth(char, used)
      if used + size > width - 1 then
        break
      end
      part, used = part .. char, used + size
    end
    if part ~= "" then
      local segment = vim.deepcopy(item)
      segment.text = part
      if segment.source_start and #item.text == item.source_end - item.source_start then
        segment.source_end = segment.source_start + #part
      end
      result[#result + 1] = segment
    end
    if #part < #item.text then
      break
    end
  end
  -- Selecting every retained fragment is not the same as selecting a complete
  -- label. Preserve that distinction before the omitted tail is discarded.
  local original, retained = {}, {}
  local function key(item)
    return tostring(item.full_start) .. ":" .. tostring(item.full_end)
  end
  for _, item in ipairs(pieces) do
    if item.kind == "node" then
      original[key(item)] = (original[key(item)] or 0) + #item.text
    end
  end
  for _, item in ipairs(result) do
    if item.kind == "node" then
      retained[key(item)] = (retained[key(item)] or 0) + #item.text
    end
  end
  for _, item in ipairs(result) do
    if item.kind == "node" and retained[key(item)] < original[key(item)] then
      item.node_complete = false
    end
  end
  result[#result + 1] = {
    text = "…",
    kind = "omission",
    source_start = cell.start_col,
    source_end = cell.end_col,
    full_start = cell.start_col,
    full_end = cell.end_col,
    group = "MdReadableOmission",
  }
  return result, true
end
local function cell_pieces(ctx, row, cell)
  return inline.parse(
    ctx.document.lines[row.source_row + 1],
    row.source_row,
    ctx.document.links,
    ctx.opts,
    cell.start_col,
    cell.end_col
  )
end
local function metadata(ctx, display_row, row, cell, a, b, omitted, column, block)
  ctx.result.cells[#ctx.result.cells + 1] = {
    row = display_row,
    start_col = a,
    end_col = b,
    source_row = row.source_row,
    source_start = cell.start_col,
    source_end = cell.end_col,
    text = cell.text,
    omitted = omitted,
    column = column,
    table_start = block.start_row,
  }
end
function M.render(block, ctx)
  local cols, width = #block.alignments, math.max(ctx.opts.width or 80, 4)
  local max_cell = ((ctx.opts.table or {}).max_cell_width or 32)
  local widths, prepared = {}, {}
  for c = 1, cols do
    widths[c] = 1
  end
  for r, row in ipairs(block.rows) do
    prepared[r] = {}
    for c, cell in ipairs(row.cells) do
      prepared[r][c] = cell_pieces(ctx, row, cell)
      widths[c] = math.max(widths[c], math.min(max_cell, vim.fn.strdisplaywidth(display(prepared[r][c]))))
    end
  end
  -- Narrow layouts show each field on its own line; no column is silently lost.
  if width < cols * 4 + 1 then
    for r, row in ipairs(block.rows) do
      if r > 1 then
        ctx.emit({ { text = "─", group = "MdReadableTableBorder" } }, row.source_row, false)
      end
      for c, cell in ipairs(row.cells) do
        local items, omitted = clipped(prepared[r][c], math.max(1, width - 2), cell)
        table.insert(items, 1, { text = tostring(c) .. " ", group = "MdReadableMuted" })
        local display_row = ctx.emit(items, row.source_row, false)
        metadata(ctx, display_row, row, cell, #tostring(c) + 1, #ctx.result.lines[display_row + 1], omitted, c, block)
      end
    end
    return
  end
  local budget = width - cols * 3 - 1
  local function total()
    local sum = 0
    for _, w in ipairs(widths) do
      sum = sum + w
    end
    return sum
  end
  while total() > budget do
    local widest = 1
    for c = 2, cols do
      if widths[c] >= widths[widest] then
        widest = c
      end
    end
    if widths[widest] <= 1 then
      break
    end
    widths[widest] = widths[widest] - 1
  end
  for r, row in ipairs(block.rows) do
    local pieces, cells, bytes = { { text = "│", group = "MdReadableTableBorder" } }, {}, #"│"
    for c, cell in ipairs(row.cells) do
      local value, omitted = clipped(prepared[r][c], widths[c], cell)
      local remaining = widths[c] - vim.fn.strdisplaywidth(display(value))
      local left = block.alignments[c] == "right" and remaining
        or block.alignments[c] == "center" and math.floor(remaining / 2)
        or 0
      local padding = string.rep(" ", 1 + left)
      pieces[#pieces + 1] = { text = padding }
      bytes = bytes + #padding
      local start = bytes
      for _, item in ipairs(value) do
        if r == 1 and item.kind ~= "omission" then
          item.group = "MdReadableTableHeader"
        end
        pieces[#pieces + 1] = item
        bytes = bytes + #item.text
      end
      cells[#cells + 1] = { cell = cell, a = start, b = bytes, omitted = omitted, c = c }
      padding = string.rep(" ", 1 + remaining - left) .. "│"
      pieces[#pieces + 1] = { text = padding, group = "MdReadableTableBorder" }
      bytes = bytes + #padding
    end
    local display_row = ctx.emit(pieces, row.source_row, false)
    for _, cell in ipairs(cells) do
      metadata(ctx, display_row, row, cell.cell, cell.a, cell.b, cell.omitted, cell.c, block)
    end
    if r == 1 then
      local chunks = {}
      for _, w in ipairs(widths) do
        chunks[#chunks + 1] = string.rep("─", w + 2)
      end
      ctx.emit(
        { { text = "├" .. table.concat(chunks, "┼") .. "┤", group = "MdReadableTableBorder" } },
        block.start_row + 1,
        false
      )
    end
  end
end
return M
