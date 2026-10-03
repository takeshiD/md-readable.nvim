local M = {}
function M.render(block, ctx)
  if block.type == "tabs" then
    local active = (ctx.opts.tabs or {})[block.start_row] or 1
    if type(active) == "string" then
      for i, tab in ipairs(block.tabs) do
        if tab.id == active then
          active = i
          break
        end
      end
    end
    if type(active) ~= "number" or not block.tabs[active] then
      active = 1
    end
    local pieces, labels = {}, {}
    for i, tab in ipairs(block.tabs) do
      pieces[#pieces + 1] = {
        text = (i == active and "[" or " ") .. tab.title .. (i == active and "] " or "  "),
        group = i == active and "MdReadableTabActive" or "MdReadableMuted",
      }
      labels[#labels + 1] = tab.title
    end
    local row = ctx.emit(pieces, block.start_row, true)
    ctx.result.controls[#ctx.result.controls + 1] =
      { row = row, source_row = block.start_row, kind = "tabs", labels = labels, active = active }
    local selected = block.tabs[active]
    ctx.body(selected.body_start, selected.body_end, selected.indent)
  else
    local open = block.type ~= "details" or (ctx.opts.expanded or {})[block.start_row]
    if block.type == "details" and open == nil then
      open = block.open
    end
    local marker = block.type == "details" and (open and "▾ " or "▸ ") or "▌ "
    local title_row = block.summary_row or block.start_row
    local source = ctx.document.lines[title_row + 1]
    local start = source and source:find(block.title, 1, true)
    local title_piece = { text = block.title, group = "MdReadableCallout" }
    if start then
      title_piece.source_start, title_piece.source_end = start - 1, start - 1 + #block.title
    end
    local row = ctx.emit({ { text = marker, group = "MdReadableCallout" }, title_piece }, title_row, true)
    if block.type == "details" then
      ctx.result.controls[#ctx.result.controls + 1] =
        { row = row, source_row = block.start_row, kind = "details", expanded = not not open }
    end
    if open then
      ctx.body(block.body_start, block.body_end, block.indent, block.strip_quote)
    end
  end
end
return M
