local M = {}
--- Pieces for one source row of a heading, quote, list or plain block.
---@param block MdReadableBlock
---@param document MdReadableDocument
---@param row integer 0-based
---@param opts? MdReadableRenderOptions
---@return MdReadableRenderPiece[]
function M.pieces(block, document, row, opts)
  local line, pieces, start = document.lines[row + 1], {}, 0
  ---@param text string
  ---@param group string
  local function prefix(text, group)
    pieces[#pieces + 1] = { text = text, group = group }
  end
  if block.type == "heading" then
    start = block.text_col or 0
  elseif block.type == "quote" then
    local a = line:match("^%s*([>%s]+)") or ""
    local _, depth = a:gsub(">", "")
    start = #a
    prefix(string.rep("│ ", math.max(depth, 1)), "MdReadableQuote")
  elseif block.type == "list" then
    local indent, marker, spacing = line:match("^(%s*)([-+*])(%s+)")
    if not marker then
      indent, marker, spacing = line:match("^(%s*)(%d+[.)])(%s+)")
    end
    start = #(indent or "") + #(marker or "") + #(spacing or "")
    prefix((indent or "") .. (#marker == 1 and "• " or marker .. " "), "MdReadableQuote")
    local task = line:sub(start + 1):match("^%[([ xX])%]%s+")
    if task then
      local task_marker = line:sub(start + 1):match("^%[[ xX]%]%s+")
      prefix(task == " " and "☐ " or "☑ ", "MdReadableCheckbox")
      start = start + #task_marker
    end
  end
  local finish = block.type == "heading" and (start + #block.text) or #line
  for _, item in ipairs(require("md-readable.renderers.inline").parse(line, row, document.links, opts, start, finish)) do
    if block.type == "heading" then
      item.group = "MdReadableHeading" .. block.level
    end
    pieces[#pieces + 1] = item
  end
  return pieces
end
return M
