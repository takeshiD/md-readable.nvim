local M = { renderers = {} }
function M.register(kind, renderer) M.renderers[kind] = renderer end

-- Optional result metadata: cells expose full source cell text for inspection;
-- controls describe static details/tabs; code_blocks retain language and ranges.
function M.render(document, opts)
  opts = opts or {}
  local result = { lines = {}, segments = {}, row_map = {}, highlights = {}, images = {}, cells = {}, controls = {}, code_blocks = {} }
  local ctx = { document = document, opts = opts, result = result }
  local width = math.max(1, opts.width or 80)
  local media = opts.media or {}
  local image_height = media.enabled == false and 0 or (opts.image_height or media.image_height or 8)
  local function add_segment(item, row, a, b, source_row, source_a, source_b)
    if source_a == nil then return end
    local previous = result.segments[#result.segments]
    local kind = item.kind or "text"
    if previous and previous.row == row and previous.end_col == a and previous.source_row == source_row
      and previous.source_end == source_a and previous.kind == kind and previous.full_start == item.full_start
      and previous.full_end == item.full_end and (b - a == source_b - source_a)
      and (previous.end_col - previous.start_col == previous.source_end - previous.source_start) then
      previous.end_col, previous.source_end = b, source_b
    else result.segments[#result.segments + 1] = { row = row, start_col = a, end_col = b, source_row = source_row,
      source_start = source_a, source_end = source_b, kind = kind, full_start = item.full_start, full_end = item.full_end } end
  end
  function ctx.emit(pieces, source_row, wrap)
    local first_row, line, cells, row = #result.lines, "", 0, #result.lines
    local function flush()
      result.lines[#result.lines + 1], result.row_map[#result.row_map + 1] = line, source_row
      row, line, cells = #result.lines, "", 0
    end
    for _, item in ipairs(pieces) do
      local consumed = 0
      for index = 0, vim.fn.strchars(item.text, true) - 1 do
        local char = vim.fn.strcharpart(item.text, index, 1, true)
        local display = char == "\t" and string.rep(" ", (opts.tabstop or 4) - cells % (opts.tabstop or 4)) or char
        local size = vim.fn.strdisplaywidth(display)
        if wrap ~= false and cells > 0 and cells + size > width then flush() end
        local start = #line
        line, cells = line .. display, cells + size
        local source_a, source_b
        if item.source_start then
          if #item.text == item.source_end - item.source_start then source_a, source_b = item.source_start + consumed, item.source_start + consumed + #char
          else source_a, source_b = item.source_start, item.source_end end
        end
        add_segment(item, row, start, #line, source_row, source_a, source_b)
        if item.group then
          local previous = result.highlights[#result.highlights]
          if previous and previous.row == row and previous.end_col == start and previous.group == item.group then previous.end_col = #line
          else result.highlights[#result.highlights + 1] = { row = row, start_col = start, end_col = #line, group = item.group } end
        end
        consumed = consumed + #char
      end
    end
    flush()
    return first_row
  end
  local render_blocks
  function ctx.body(start_row, end_row, indent, strip_quote)
    local parent_document = ctx.document
    local lines = parent_document.lines
    if indent or strip_quote then
      local transformed, offsets = vim.deepcopy(lines), {}
      for row = start_row, end_row - 1 do
        local prefix = strip_quote and (lines[row + 1]:match("^%s*>%s?") or "") or lines[row + 1]:sub(1, indent or 0):match("^%s*")
        offsets[row] = #prefix; transformed[row + 1] = lines[row + 1]:sub(#prefix + 1)
      end
      local old_document, first_segment, first_cell = ctx.document, #result.segments + 1, #result.cells + 1
      local nested = require("md-readable.document.parser").parse(transformed)
      ctx.document = nested
      render_blocks(require("md-readable.document.blocks").scan(transformed, start_row, end_row), nested)
      for index = first_segment, #result.segments do
        local segment = result.segments[index]; local offset = offsets[segment.source_row] or 0
        segment.source_start, segment.source_end = segment.source_start + offset, segment.source_end + offset
        if segment.full_start then segment.full_start, segment.full_end = segment.full_start + offset, segment.full_end + offset end
      end
      for index = first_cell, #result.cells do
        local cell = result.cells[index]; local offset = offsets[cell.source_row] or 0
        cell.source_start, cell.source_end = cell.source_start + offset, cell.source_end + offset
      end
      ctx.document = old_document
    else render_blocks(require("md-readable.document.blocks").scan(lines, start_row, end_row), parent_document) end
  end
  render_blocks = function(blocks, doc)
    for _, block in ipairs(blocks) do
      if M.renderers[block.type] then M.renderers[block.type](block, ctx)
      elseif block.type == "table" then require("md-readable.renderers.table").render(block, ctx)
      elseif block.type == "callout" or block.type == "details" or block.type == "tabs" then require("md-readable.renderers.extensions").render(block, ctx)
      elseif block.type == "frontmatter" or block.type == "reference" then -- Kept in source, intentionally absent from reading text.
      elseif block.type == "rule" then ctx.emit({ { text = string.rep("─", math.min(width, 40)), group = "MdReadableRule" } }, block.start_row, false)
      elseif block.type == "code" then
        local label = block.language ~= "" and block.language or "Code"
        local header_row = ctx.emit({ { text = "┌ " .. label, group = "MdReadableMuted" } }, block.start_row, true)
        local body_lines, body_rows = {}, {}
        for row = block.body_start, block.body_end - 1 do
          local text = doc.lines[row + 1]; local offset = math.min(block.indent or 0, #text)
          body_lines[#body_lines + 1] = text:sub(offset + 1)
          body_rows[#body_rows + 1] = ctx.emit({ { text = text:sub(offset + 1), source_start = offset, source_end = #text, group = "MdReadableCodeBlock" } }, row, true)
        end
        result.code_blocks[#result.code_blocks + 1] = { row = header_row, end_row = #result.lines, source_row = block.start_row, body_start = block.body_start, body_end = block.body_end, language = block.language }
        for _, hl in ipairs(require("md-readable.renderers.code").highlights(body_lines, block.language)) do
          local source_row = block.body_start + hl.row
          for _, segment in ipairs(result.segments) do
            if segment.source_row == source_row and segment.row >= header_row then
              local offset = block.indent or 0
              local a, b = math.max(segment.source_start, hl.start_col + offset), math.min(segment.source_end, hl.end_col + offset)
              if a < b then result.highlights[#result.highlights + 1] = { row = segment.row, start_col = segment.start_col + a - segment.source_start,
                end_col = segment.start_col + b - segment.source_start, group = hl.group } end
            end
          end
        end
        if block.language:lower() == "mermaid" then
          result.images[#result.images + 1] = { kind = "mermaid", row = #result.lines, label_row = header_row, source_row = block.start_row,
            code = table.concat(body_lines, "\n"), alt = "Mermaid diagram", height = image_height, width = width }
          for _ = 1, image_height do ctx.emit({}, block.start_row, false) end
        end
      else
        for row = block.start_row, (block.type == "heading" and block.start_row or block.end_row - 1) do
          local display_row = ctx.emit(require("md-readable.renderers.text").pieces(block, doc, row, opts), row, true)
          for _, link in ipairs(doc.links) do
            if link.kind == "image" and link.range.start.row == row then
              result.images[#result.images + 1] = { kind = "image", row = #result.lines, label_row = display_row, source_row = row,
                path = link.target, alt = link.text, height = image_height, width = width }
              for _ = 1, image_height do ctx.emit({}, row, false) end
            end
          end
        end
      end
    end
  end
  render_blocks(document.blocks, document)
  if #result.lines == 0 then result.lines, result.row_map = { "" }, { 0 } end
  return result
end
return M
