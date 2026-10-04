local M = {}
function M.register(parser)
  require("md-readable.document.blocks").register(parser)
end
function M.parse(lines, opts)
  opts = opts or {}
  local original = vim.deepcopy(lines)
  local blocks = require("md-readable.document.blocks").scan(original)
  local links, tables, excluded, outline_blocks = {}, {}, {}, {}
  local function collect(items, source_lines)
    for _, block in ipairs(items) do
      outline_blocks[#outline_blocks + 1] = block
      if block.type == "code" or block.type == "frontmatter" or block.type == "reference" then
        for row = block.start_row, block.end_row - 1 do
          excluded[row] = true
        end
      elseif block.type == "table" then
        local source_table = vim.deepcopy(block)
        local removed_prefix = #original[block.start_row + 1] - #source_lines[block.start_row + 1]
        source_table.prefix = original[block.start_row + 1]:sub(1, removed_prefix) .. (block.prefix or "")
        for _, table_row in ipairs(source_table.rows) do
          local offset = #original[table_row.source_row + 1] - #source_lines[table_row.source_row + 1]
          for _, cell in ipairs(table_row.cells) do
            cell.start_col, cell.end_col = cell.start_col + offset, cell.end_col + offset
          end
        end
        tables[#tables + 1] = source_table
      elseif block.type == "callout" or block.type == "details" or block.type == "tabs" then
        local bodies = block.type == "tabs" and block.tabs or { block }
        for _, body in ipairs(bodies) do
          local transformed = vim.deepcopy(source_lines)
          for row = body.body_start, body.body_end - 1 do
            if body.indent then
              transformed[row + 1] = transformed[row + 1]:sub(body.indent + 1)
            elseif body.strip_quote then
              transformed[row + 1] = transformed[row + 1]:gsub("^%s*>%s?", "")
            end
          end
          collect(require("md-readable.document.blocks").scan(transformed, body.body_start, body.body_end), transformed)
        end
      end
    end
  end
  collect(blocks, original)
  local reference_lines = vim.deepcopy(original)
  for row in pairs(excluded) do
    if not original[row + 1]:match("^%s*%[[^%]]+%]:") then
      reference_lines[row + 1] = ""
    end
  end
  -- Definitions inside code/frontmatter must not resolve prose links.
  local function blank_code(items)
    for _, block in ipairs(items) do
      if block.type == "code" or block.type == "frontmatter" then
        for row = block.start_row, block.end_row - 1 do
          reference_lines[row + 1] = ""
        end
      end
    end
  end
  blank_code(outline_blocks)
  local references = require("md-readable.document.links").references(reference_lines)
  for row, line in ipairs(original) do
    if not excluded[row - 1] then
      for _, link in ipairs(require("md-readable.document.links").parse(line, row - 1, references)) do
        links[#links + 1] = link
      end
    end
  end
  -- Footnotes by normalized id: definition row and the rows referring to it.
  local footnotes = {}
  for key, ref in pairs(references) do
    if ref.footnote then
      footnotes[key:sub(2)] = { id = ref.id, row = ref.row, references = {} }
    end
  end
  for _, link in ipairs(links) do
    if link.kind == "footnote" then
      local note = footnotes[link.target:sub(2):lower()]
      if note then
        note.references[#note.references + 1] = link.range
      end
    end
  end
  return {
    lines = original,
    blocks = blocks,
    links = links,
    footnotes = footnotes,
    tables = tables,
    references = references,
    headings = require("md-readable.document.outline").build(outline_blocks, original),
    changedtick = opts.changedtick or 0,
    bufnr = opts.bufnr,
    path = opts.path,
  }
end
return M
