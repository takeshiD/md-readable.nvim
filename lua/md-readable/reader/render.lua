---@alias MdReadableBlockRenderer fun(block:MdReadableBlock, ctx:MdReadableRenderContext)
---@class MdReadableRenderMediaOptions
---@field enabled? boolean false reserves no rows for media
---@field image_height? integer Rows reserved per image or diagram
---@field reserve? fun(descriptor:MdReadableRenderedImage):boolean false when the media cannot be drawn
-- Render options: a (partial) configuration plus per-session state.
---@class MdReadableRenderOptions: MdReadableUserConfig
---@field tabstop? integer
---@field expanded? table<integer, boolean> See MdReadableSession.expanded
---@field tabs? table<integer, integer> See MdReadableSession.tabs
---@field media? MdReadableRenderMediaOptions
---@field image_height? integer Overrides media.image_height
---@field max_url_width? integer
---@class MdReadableRenderModule
---@field renderers table<string, MdReadableBlockRenderer> Custom renderers by block type
local M = { renderers = {} }
---@param kind string Block type
---@param renderer MdReadableBlockRenderer
function M.register(kind, renderer)
  M.renderers[kind] = renderer
end

-- Optional result metadata: cells expose full source cell text for inspection;
-- controls describe static details/tabs; code_blocks retain language and ranges.
-- source_rows lists every original row contributing to each display line, while
-- row_map retains the first contributor. node_complete=false prevents copying a
-- truncated visible link label as though its omitted tail had been selected.
---@param document MdReadableDocument
---@param opts? MdReadableRenderOptions
---@return MdReadableRendered
function M.render(document, opts)
  opts = opts or {}
  ---@type MdReadableRendered
  local result = {
    lines = {},
    segments = {},
    row_map = {},
    source_rows = {},
    highlights = {},
    images = {},
    cells = {},
    controls = {},
    code_blocks = {},
  }
  ---@type MdReadableRenderContext
  ---@diagnostic disable-next-line: missing-fields -- emit and body are assigned below
  local ctx = { document = document, opts = opts, result = result }
  local width = math.max(1, opts.width or 80)
  local media = opts.media or {}
  local image_height = media.enabled == false and 0 or (opts.image_height or media.image_height or 8)
  -- Records a media descriptor and reserves its rows only when it can be
  -- drawn; media.reserve rejects known failures (missing file, no mmdc, ...).
  ---@param descriptor table MdReadableRenderedImage without row, width and height
  ---@param source_row integer
  local function add_media(descriptor, source_row)
    descriptor.row, descriptor.width = #result.lines, width
    descriptor.height = image_height
    if image_height > 0 and media.reserve and not media.reserve(descriptor) then
      descriptor.height = 0
    end
    result.images[#result.images + 1] = descriptor
    for _ = 1, descriptor.height do
      ctx.emit({}, source_row, false)
    end
  end
  -- Adds or extends a segment; display columns a..b map to source_a..source_b.
  ---@param item MdReadableRenderPiece
  ---@param row integer Display row (0-based)
  ---@param a integer
  ---@param b integer Exclusive
  ---@param source_row integer
  ---@param source_a? integer nil for decoration (no segment)
  ---@param source_b? integer
  local function add_segment(item, row, a, b, source_row, source_a, source_b)
    if source_a == nil then
      return
    end
    ---@cast source_b integer
    local previous = result.segments[#result.segments]
    local kind = item.kind or "text"
    if
      previous
      and previous.row == row
      and previous.end_col == a
      and previous.source_row == source_row
      and previous.source_end == source_a
      and previous.kind == kind
      and previous.full_start == item.full_start
      and previous.full_end == item.full_end
      and previous.node_complete == item.node_complete
      and (b - a == source_b - source_a)
      and (previous.end_col - previous.start_col == previous.source_end - previous.source_start)
    then
      previous.end_col, previous.source_end = b, source_b
    else
      result.segments[#result.segments + 1] = {
        row = row,
        start_col = a,
        end_col = b,
        source_row = source_row,
        source_start = source_a,
        source_end = source_b,
        kind = kind,
        full_start = item.full_start,
        full_end = item.full_end,
        node_complete = item.node_complete,
      }
    end
  end
  ---@param pieces MdReadableRenderPiece[]
  ---@param source_row integer
  ---@param wrap? boolean false keeps the pieces on one display line
  ---@return integer first_row First emitted display row (0-based)
  function ctx.emit(pieces, source_row, wrap)
    local first_row, line, cells, row = #result.lines, "", 0, #result.lines
    local contributors, seen = {}, {}
    local function flush()
      if #contributors == 0 then
        contributors = { source_row }
      end
      result.lines[#result.lines + 1], result.row_map[#result.row_map + 1] = line, contributors[1]
      result.source_rows[#result.source_rows + 1] = contributors
      row, line, cells = #result.lines, "", 0
      contributors, seen = {}, {}
    end
    for _, item in ipairs(pieces) do
      local consumed = 0
      for index = 0, vim.fn.strchars(item.text, true) - 1 do
        local char = vim.fn.strcharpart(item.text, index, 1, true)
        if char == "\n" or char == "\r" then
          char = " "
        end
        local display = char == "\t" and string.rep(" ", (opts.tabstop or 4) - cells % (opts.tabstop or 4)) or char
        local size = vim.fn.strdisplaywidth(display)
        if wrap ~= false and cells > 0 and cells + size > width then
          flush()
        end
        local start = #line
        line, cells = line .. display, cells + size
        local source_a, source_b
        if item.source_start then
          if #item.text == item.source_end - item.source_start then
            source_a, source_b = item.source_start + consumed, item.source_start + consumed + #char
          else
            source_a, source_b = item.source_start, item.source_end
          end
        end
        local item_source_row = item.source_row or source_row
        if source_a ~= nil and not seen[item_source_row] then
          contributors[#contributors + 1], seen[item_source_row] = item_source_row, true
        end
        add_segment(item, row, start, #line, item_source_row, source_a, source_b)
        if item.group then
          local previous = result.highlights[#result.highlights]
          if previous and previous.row == row and previous.end_col == start and previous.group == item.group then
            previous.end_col = #line
          else
            result.highlights[#result.highlights + 1] =
              { row = row, start_col = start, end_col = #line, group = item.group }
          end
        end
        consumed = consumed + #char
      end
    end
    flush()
    return first_row
  end
  ---@param char string
  ---@return boolean
  local function cjk(char)
    local cp = vim.fn.char2nr(char)
    return (cp >= 0x2E80 and cp <= 0xA4CF)
      or (cp >= 0xAC00 and cp <= 0xD7AF)
      or (cp >= 0xF900 and cp <= 0xFAFF)
      or (cp >= 0xFE30 and cp <= 0xFE4F)
      or (cp >= 0xFF00 and cp <= 0xFFEF)
      or (cp >= 0x20000 and cp <= 0x323AF)
  end
  ---@param doc MdReadableDocument
  ---@param row integer
  ---@return MdReadableRenderPiece[] pieces
  ---@return boolean hard Ends with a hard line break
  ---@return string text Visible text
  local function paragraph_pieces(doc, row)
    local line = doc.lines[row + 1]
    local slashes = line:match("(\\+)$") or ""
    local hard = line:match("  +$") ~= nil or #slashes % 2 == 1
    local last = #slashes % 2 == 1 and #line - 1 or #(line:gsub("%s+$", ""))
    local first = #(line:match("^ ? ? ?") or "")
    local pieces = require("md-readable.renderers.inline").parse(line, row, doc.links, opts, first, last)
    local visible = {}
    for _, piece in ipairs(pieces) do
      piece.source_row = row
      visible[#visible + 1] = piece.text
    end
    return pieces, hard, table.concat(visible)
  end
  ---@type fun(blocks:MdReadableBlock[], doc:MdReadableDocument)
  local render_blocks
  ---@param start_row integer
  ---@param end_row integer Exclusive
  ---@param indent? integer Leading columns removed from each row
  ---@param strip_quote? boolean Remove blockquote markers
  function ctx.body(start_row, end_row, indent, strip_quote)
    local parent_document = ctx.document
    local lines = parent_document.lines
    if indent or strip_quote then
      local transformed, offsets = vim.deepcopy(lines), {}
      for row = start_row, end_row - 1 do
        local prefix = strip_quote and (lines[row + 1]:match("^%s*>%s?") or "")
          or lines[row + 1]:sub(1, indent or 0):match("^%s*")
        offsets[row] = #prefix
        transformed[row + 1] = lines[row + 1]:sub(#prefix + 1)
      end
      local old_document, first_segment, first_cell = ctx.document, #result.segments + 1, #result.cells + 1
      local nested = require("md-readable.document.parser").parse(transformed)
      ctx.document = nested
      render_blocks(require("md-readable.document.blocks").scan(transformed, start_row, end_row), nested)
      for index = first_segment, #result.segments do
        local segment = result.segments[index]
        local offset = offsets[segment.source_row] or 0
        segment.source_start, segment.source_end = segment.source_start + offset, segment.source_end + offset
        if segment.full_start then
          segment.full_start, segment.full_end = segment.full_start + offset, segment.full_end + offset
        end
      end
      for index = first_cell, #result.cells do
        local cell = result.cells[index]
        local offset = offsets[cell.source_row] or 0
        cell.source_start, cell.source_end = cell.source_start + offset, cell.source_end + offset
      end
      ctx.document = old_document
    else
      render_blocks(require("md-readable.document.blocks").scan(lines, start_row, end_row), parent_document)
    end
  end
  render_blocks = function(blocks, doc)
    local consumed = {}
    ---@param block? MdReadableBlock
    ---@return boolean
    local function joinable(block)
      if not block or block.type ~= "paragraph" then
        return false
      end
      if doc.lines[block.start_row + 1]:match("^%s*</?[%a][%w-]*[%s>/]") then
        return false
      end
      for _, link in ipairs(doc.links) do
        if link.kind == "image" and link.range.start.row == block.start_row then
          return false
        end
      end
      return true
    end
    for block_index, block in ipairs(blocks) do
      if consumed[block_index] then -- Joined into the preceding ordinary paragraph.
      elseif M.renderers[block.type] then
        M.renderers[block.type](block, ctx)
      elseif block.type == "table" and (opts.table or {}).enable == false then
        for row = block.start_row, block.end_row - 1 do
          local text = doc.lines[row + 1]
          ctx.emit({ { text = text, source_start = 0, source_end = #text } }, row, true)
        end
      elseif block.type == "table" then
        require("md-readable.renderers.table").render(block, ctx)
      elseif block.type == "callout" or block.type == "details" or block.type == "tabs" then
        require("md-readable.renderers.extensions").render(block, ctx)
      elseif block.type == "frontmatter" or block.type == "reference" then -- Kept in source, intentionally absent from reading text.
      elseif block.type == "footnote" then
        local previous = block_index - 1
        while blocks[previous] and blocks[previous].type == "blank" do
          previous = previous - 1
        end
        if not blocks[previous] or blocks[previous].type ~= "footnote" then
          local title = "── Footnotes "
          local fill = math.max(0, math.min(width, 40) - vim.fn.strdisplaywidth(title))
          ctx.emit({ { text = title .. string.rep("─", fill), group = "MdReadableMuted" } }, block.start_row, false)
        end
        local line = doc.lines[block.start_row + 1]
        local label_start = #(line:match("^ ? ? ?") or "")
        local pieces = {
          {
            text = "[" .. block.id .. "] ",
            source_start = label_start,
            source_end = block.label_end,
            source_row = block.start_row,
            group = "MdReadableFootnote",
          },
        }
        for row = block.start_row, block.end_row - 1 do
          local text = doc.lines[row + 1]
          if text:match("%S") then
            local first = row == block.start_row and block.text_col or #text:match("^%s*")
            local last = #(text:gsub("%s+$", ""))
            if row > block.start_row then
              pieces[#pieces + 1] = { text = " " }
            end
            for _, piece in
              ipairs(require("md-readable.renderers.inline").parse(text, row, doc.links, opts, first, last))
            do
              piece.source_row = row
              pieces[#pieces + 1] = piece
            end
          end
        end
        ctx.emit(pieces, block.start_row, true)
      elseif block.type == "rule" then
        ctx.emit(
          { { text = string.rep("─", math.min(width, 40)), group = "MdReadableRule" } },
          block.start_row,
          false
        )
      elseif block.type == "code" then
        -- Shiki-like panel: a top row carrying the icon and language in the
        -- chosen corner, one blank column on the left, a bottom row, and the
        -- block background across the full body width. All of it is decoration.
        local code_opts = opts.code or {}
        local first_highlight = #result.highlights + 1
        local label, label_width = {}, 0
        if block.language ~= "" then
          local icon, icon_group
          if code_opts.icons then
            icon, icon_group = require("md-readable.renderers.code").icon(block.language, code_opts.icons)
          end
          if icon then
            label[#label + 1] = { text = icon .. " ", group = icon_group }
          end
          label[#label + 1] = { text = block.language, group = "MdReadableCodeBlockLabel" }
        end
        for _, item in ipairs(label) do
          label_width = label_width + vim.fn.strdisplaywidth(item.text)
        end
        local lead = code_opts.label == "right" and math.max(1, width - label_width - 1) or 1
        local header_row = ctx.emit({ { text = string.rep(" ", lead) }, unpack(label) }, block.start_row, false)
        local body_lines, body_rows = {}, {}
        for row = block.body_start, block.body_end - 1 do
          local text = doc.lines[row + 1]
          local offset = math.min(block.indent or 0, #text)
          body_lines[#body_lines + 1] = text:sub(offset + 1)
          body_rows[#body_rows + 1] = ctx.emit({
            { text = " " },
            { text = text:sub(offset + 1), source_start = offset, source_end = #text, group = "MdReadableCodeBlock" },
          }, row, true)
        end
        ctx.emit({}, block.end_row - 1, false)
        -- Background first, so labels and syntax colors are drawn over it.
        local fill = {}
        for row = header_row, #result.lines - 1 do
          local line = result.lines[row + 1]
          line = line .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(line)))
          result.lines[row + 1] = line
          fill[#fill + 1] = { row = row, start_col = 0, end_col = #line, group = "MdReadableCodeBlock" }
        end
        for index, item in ipairs(fill) do
          table.insert(result.highlights, first_highlight + index - 1, item)
        end
        result.code_blocks[#result.code_blocks + 1] = {
          row = header_row,
          end_row = #result.lines,
          source_row = block.start_row,
          body_start = block.body_start,
          body_end = block.body_end,
          language = block.language,
        }
        for _, hl in ipairs(require("md-readable.renderers.code").highlights(body_lines, block.language, opts.code)) do
          local source_row = block.body_start + hl.row
          for _, segment in ipairs(result.segments) do
            if segment.source_row == source_row and segment.row >= header_row then
              local offset = block.indent or 0
              local a, b =
                math.max(segment.source_start, hl.start_col + offset), math.min(segment.source_end, hl.end_col + offset)
              if a < b then
                result.highlights[#result.highlights + 1] = {
                  row = segment.row,
                  start_col = segment.start_col + a - segment.source_start,
                  end_col = segment.start_col + b - segment.source_start,
                  group = hl.group,
                }
              end
            end
          end
        end
        if block.language:lower() == "mermaid" then
          add_media({
            kind = "mermaid",
            label_row = header_row,
            source_row = block.start_row,
            code = table.concat(body_lines, "\n"),
            alt = "Mermaid diagram",
          }, block.start_row)
        end
      elseif joinable(block) then
        local pieces, hard, previous_text = paragraph_pieces(doc, block.start_row)
        local next_index = block_index + 1
        while not hard and joinable(blocks[next_index]) do
          local following, next_hard, next_text = paragraph_pieces(doc, blocks[next_index].start_row)
          local last_char =
            vim.fn.strcharpart(previous_text, math.max(0, vim.fn.strchars(previous_text, true) - 1), 1, true)
          local first_char = vim.fn.strcharpart(next_text, 0, 1, true)
          if not (cjk(last_char) and cjk(first_char)) then
            pieces[#pieces + 1] = { text = " " }
          end
          for _, piece in ipairs(following) do
            pieces[#pieces + 1] = piece
          end
          consumed[next_index], hard, previous_text = true, next_hard, next_text
          next_index = next_index + 1
        end
        ctx.emit(pieces, block.start_row, true)
      else
        for row = block.start_row, (block.type == "heading" and block.start_row or block.end_row - 1) do
          local display_row = ctx.emit(require("md-readable.renderers.text").pieces(block, doc, row, opts), row, true)
          for _, link in ipairs(doc.links) do
            if link.kind == "image" and link.range.start.row == row then
              add_media({
                kind = "image",
                label_row = display_row,
                source_row = row,
                path = link.target,
                alt = link.text,
              }, row)
            end
          end
        end
        -- H1/H2 get a display-only rule so structure does not depend on color.
        if block.type == "heading" and block.level <= 2 and opts.heading_rules ~= false then
          ctx.emit({
            {
              text = string.rep(block.level == 1 and "═" or "─", width),
              group = "MdReadableHeading" .. block.level,
            },
          }, block.end_row - 1, false)
        end
      end
    end
  end
  render_blocks(document.blocks, document)
  if #result.lines == 0 then
    result.lines, result.row_map, result.source_rows = { "" }, { 0 }, { { 0 } }
  end
  return result
end
return M
