local M = {}
local function title(value)
  return value and value:match("^%s*[\"']?(.-)[\"']?%s*$")
end
function M.parse(lines, row, limit)
  local line, n = lines[row + 1], math.min(limit or #lines, #lines)
  local kind, label = line:match("^%s*>%s*%[!([%w_-]+)%][+-]?%s*(.*)$")
  if kind then
    local finish = row + 1
    while finish < n and lines[finish + 1]:match("^%s*>") do
      finish = finish + 1
    end
    return {
      type = "callout",
      start_row = row,
      end_row = finish,
      kind = kind:lower(),
      title = label ~= "" and label or kind,
      body_start = row + 1,
      body_end = finish,
      strip_quote = true,
    }
  end
  if line:match("^%s*<details[%s>]") then
    local finish, depth, summary, summary_row = row + 1, 1, "Details", row
    local inline_summary = line:match("<summary[^>]*>(.-)</summary>")
    if inline_summary then
      summary = inline_summary
    end
    while finish < n do
      local current = lines[finish + 1]
      if current:match("<details[%s>]") then
        depth = depth + 1
      end
      if current:match("</details>") then
        depth = depth - 1
      end
      if depth == 0 then
        break
      end
      if depth == 1 then
        local value = current:match("<summary[^>]*>(.-)</summary>")
        if value then
          summary, summary_row = value, finish
        end
      end
      finish = finish + 1
    end
    if finish < n then
      return {
        type = "details",
        start_row = row,
        end_row = finish + 1,
        title = summary,
        summary_row = summary_row,
        body_start = summary_row + 1,
        body_end = finish,
        open = line:match("%sopen[%s=>]") ~= nil,
      }
    end
  end
  kind, label = line:match("^%s*:::([%w_-]+)%s*(.*)$")
  if kind then
    local finish, depth = row + 1, 1
    while finish < n do
      local current = lines[finish + 1]
      if current:match("^%s*:::[%w_-]") then
        depth = depth + 1
      elseif current:match("^%s*:::%s*$") then
        depth = depth - 1
      end
      if depth == 0 then
        break
      end
      finish = finish + 1
    end
    if finish < n then
      return {
        type = "callout",
        kind = kind,
        title = label ~= "" and label or kind,
        start_row = row,
        end_row = finish + 1,
        body_start = row + 1,
        body_end = finish,
      }
    end
  end
  local marker
  marker, kind, label = line:match("^%s*([!?][!?][!?])[+-]?%s+([%w_-]+)%s*(.*)$")
  if marker then
    local finish = row + 1
    while finish < n and (lines[finish + 1]:match("^    ") or lines[finish + 1]:match("^%s*$")) do
      finish = finish + 1
    end
    return {
      type = marker == "???" and "details" or "callout",
      start_row = row,
      end_row = finish,
      kind = kind,
      title = label ~= "" and title(label) or kind,
      body_start = row + 1,
      body_end = finish,
      indent = 4,
      open = line:match("%?%?%?%+") ~= nil,
    }
  end
  if line:match("^%s*<Tabs[%s>]") then
    local finish, tabs, current = row + 1, {}, nil
    while finish < n and not lines[finish + 1]:match("^%s*</Tabs>") do
      local text = lines[finish + 1]
      if text:match("^%s*<Tab[%s>]") or text:match("^%s*<TabItem[%s>]") then
        local value = text:match('label="([^"]+)"') or text:match("label='([^']+)'")
        local id = text:match('value="([^"]+)"') or text:match("value='([^']+)'")
        -- Dynamic labels are deliberately left as ordinary source text.
        if not value then
          return nil
        end
        current = { title = value, id = id or value, start_row = finish, body_start = finish + 1 }
      elseif text:match("^%s*</Tab>") or text:match("^%s*</TabItem>") then
        if current then
          current.body_end = finish
          tabs[#tabs + 1] = current
          current = nil
        end
      end
      finish = finish + 1
    end
    if finish < n and #tabs > 0 then
      return { type = "tabs", start_row = row, end_row = finish + 1, tabs = tabs }
    end
  end
  label = line:match('^%s*===%s+"([^"]+)"%s*$') or line:match("^%s*===%s+'([^']+)'%s*$")
  if label then
    local tabs, finish = {}, row
    while finish < n do
      local tab_title = lines[finish + 1]:match('^%s*===%s+"([^"]+)"%s*$')
        or lines[finish + 1]:match("^%s*===%s+'([^']+)'%s*$")
      if not tab_title then
        break
      end
      local current = { title = tab_title, id = tab_title, start_row = finish, body_start = finish + 1, indent = 4 }
      finish = finish + 1
      while finish < n and (lines[finish + 1]:match("^    ") or lines[finish + 1]:match("^%s*$")) do
        finish = finish + 1
      end
      current.body_end = finish
      tabs[#tabs + 1] = current
    end
    return { type = "tabs", start_row = row, end_row = finish, tabs = tabs }
  end
end
return M
