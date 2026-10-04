local M = {}
---@class MdReadableSearchMatch
---@field row integer 0-based source row
---@field col integer 0-based byte column
---@field text string Whole source line
---@param session MdReadableSession
---@param pattern string Vim regex
---@return MdReadableSearchMatch[]? matches
---@return string? err
function M.find(session, pattern)
  local ok, regex = pcall(vim.regex, pattern)
  if not ok then
    return nil, regex --[[@as string]]
  end
  local matches = {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(session.source_buf, 0, -1, false)) do
    local offset = 0
    while offset <= #line do
      local first, final = regex:match_str(line:sub(offset + 1))
      if not first then
        break
      end
      ---@cast final integer
      matches[#matches + 1] = { row = row - 1, col = offset + first, text = line }
      offset = offset + math.max(final, first + 1)
    end
  end
  return matches
end
---@param session MdReadableSession
---@param pattern? string Prompts when nil
function M.open(session, pattern)
  if not pattern then
    vim.ui.input({ prompt = "Search Markdown source: " }, function(value)
      if value and value ~= "" and not session.closed then
        M.open(session, value)
      end
    end)
    return
  end
  local matches, err = M.find(session, pattern)
  if not matches then
    vim.notify(tostring(err), vim.log.levels.ERROR)
    return
  end
  if #matches == 0 then
    vim.notify("md-readable: no source matches")
    return
  end
  vim.ui.select(matches, {
    prompt = "Source matches",
    format_item = function(item)
      return string.format("%d:%d  %s", item.row + 1, item.col + 1, item.text)
    end,
  }, function(item)
    if not item or session.closed then
      return
    end
    session.expanded[item.row] = true
    ---@param blocks MdReadableBlock[]
    local function reveal(blocks)
      for _, block in ipairs(blocks) do
        if item.row >= block.start_row and item.row < block.end_row then
          if block.type == "details" then
            session.expanded[block.start_row] = true
          end
          if block.type == "tabs" then
            for index, tab in ipairs(block.tabs) do
              if item.row >= tab.body_start and item.row < tab.body_end then
                session.tabs[block.start_row] = index
              end
            end
          end
        end
      end
    end
    reveal(session.document.blocks)
    for _, control in ipairs(session.rendered.controls or {}) do
      session.expanded[control.source_row] = true
    end
    session:refresh()
    session:jump_source(item.row, item.col)
  end)
end
return M
