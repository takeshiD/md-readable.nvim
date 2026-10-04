local M = {}

--- Edit a copy of `tbl` and return its formatted Markdown lines.
---@param tbl MdReadableTable
---@param action string "row_before"|"row_after"|"row_delete"|"col_before"|"col_after"|"col_delete"
---@param index integer Row index (0 = header) for row actions, column (1-based) for column actions
---@param count? integer Defaults to 1
---@return string[]? lines
---@return string? err
function M.edit(tbl, action, index, count)
  count = count or 1
  if type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
    return nil, "count must be a positive integer"
  end
  if type(index) ~= "number" or index % 1 ~= 0 then
    return nil, "index must be an integer"
  end
  local copy, columns = vim.deepcopy(tbl), #(tbl.alignments or {})
  for _, row in ipairs(tbl.rows) do
    columns = math.max(columns, #row.cells)
  end
  if columns == 0 or #tbl.rows == 0 then
    return nil, "invalid table"
  end
  copy.alignments = copy.alignments or {}
  for col = 1, columns do
    copy.alignments[col] = copy.alignments[col] or "none"
    for _, row in ipairs(copy.rows) do
      row.cells[col] = row.cells[col] or { text = "" }
    end
  end
  if action:match("^row_") then
    if index < 0 or index >= #copy.rows then
      return nil, "row index is outside the table"
    end
    if action == "row_delete" then
      if index == 0 then
        return nil, "cannot delete the header"
      end
      if index + count > #copy.rows then
        return nil, "row deletion extends past the table"
      end
      for _ = 1, count do
        table.remove(copy.rows, index + 1)
      end
    elseif action == "row_before" or action == "row_after" then
      if index == 0 and action == "row_before" then
        return nil, "cannot insert before the header"
      end
      local at = index + (action == "row_after" and 2 or 1)
      for _ = 1, count do
        local row = { cells = {} }
        for col = 1, columns do
          row.cells[col] = { text = "" }
        end
        table.insert(copy.rows, at, row)
      end
    else
      return nil, "unknown table action: " .. action
    end
  elseif action:match("^col_") then
    if index < 1 or index > columns then
      return nil, "column index is outside the table"
    end
    if action == "col_delete" then
      if count >= columns or index + count - 1 > columns then
        return nil, "column deletion would invalidate the table"
      end
      for _ = 1, count do
        table.remove(copy.alignments, index)
        for _, row in ipairs(copy.rows) do
          table.remove(row.cells, index)
        end
      end
    elseif action == "col_before" or action == "col_after" then
      local at = index + (action == "col_after" and 1 or 0)
      for _ = 1, count do
        table.insert(copy.alignments, at, "none")
        for _, row in ipairs(copy.rows) do
          table.insert(row.cells, at, { text = "" })
        end
      end
    else
      return nil, "unknown table action: " .. action
    end
  else
    return nil, "unknown table action: " .. action
  end
  return require("md-readable.table.format").format(copy)
end

return M
