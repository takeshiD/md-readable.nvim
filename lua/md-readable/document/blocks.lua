local M = { extensions = {} }
function M.register(parser)
  M.extensions[#M.extensions + 1] = parser
end

function M.scan(lines, start_row, end_row)
  local result, row = {}, start_row or 0
  local limit = end_row or #lines
  while row < limit do
    local line, block = lines[row + 1], nil
    if row == 0 and (line == "---" or line == "+++") then
      for last = 2, limit do
        if lines[last] == line or (line == "---" and lines[last] == "...") then
          block = { type = "frontmatter", start_row = 0, end_row = last }
          break
        end
      end
    end
    local indent, fence, info = line:match("^(%s*)(`+)%s*(.*)$")
    if not fence then
      indent, fence, info = line:match("^(%s*)(~+)%s*(.*)$")
    end
    if not block and fence and #fence >= 3 and #indent <= 3 then
      local finish = row + 1
      while finish < limit do
        local close = lines[finish + 1]:match("^%s*([`~]+)%s*$")
        if
          close
          and close:sub(1, 1) == fence:sub(1, 1)
          and #close >= #fence
          and not close:find(fence:sub(1, 1) == "`" and "~" or "`", 1, true)
        then
          break
        end
        finish = finish + 1
      end
      block = {
        type = "code",
        start_row = row,
        end_row = math.min(finish + 1, limit),
        body_start = row + 1,
        body_end = finish,
        language = info:match("^([^%s{]+)") or "",
        info = info,
      }
    end
    if not block then
      block = require("md-readable.document.extensions").parse(lines, row, limit)
      for _, parser in ipairs(M.extensions) do
        if not block then
          block = parser(lines, row, limit)
        end
      end
    end
    if not block then
      block = require("md-readable.document.table").parse(lines, row)
    end
    if not block then
      local hashes, text = line:match("^ ? ? ?(#+)%s+(.-)%s*$")
      if text then
        text = text:gsub("%s+#+%s*$", "")
      end
      if not hashes then
        hashes = line:match("^ ? ? ?(#+)%s*$")
        text = ""
      end
      if hashes and #hashes <= 6 then
        local prefix = line:match("^ ? ? ?#+%s*")
        block =
          { type = "heading", level = #hashes, text = text, text_col = #prefix, start_row = row, end_row = row + 1 }
      elseif
        row + 1 < limit
        and line:match("%S")
        and (lines[row + 2]:match("^ ? ? ?=+%s*$") or lines[row + 2]:match("^ ? ? ?-+%s*$"))
      then
        block = {
          type = "heading",
          level = lines[row + 2]:match("=") and 1 or 2,
          text = line:match("^%s*(.-)%s*$"),
          text_col = #(line:match("^%s*") or ""),
          start_row = row,
          end_row = row + 2,
        }
      elseif line:match("^%s*$") then
        block = { type = "blank", start_row = row, end_row = row + 1 }
      elseif line:match("^ ? ? ?%[%^[^%]%s]+%]:") then
        -- Footnote definition. Indented lines continue it, as do blank lines
        -- followed by a line indented by four spaces or a tab.
        local finish = row + 1
        while finish < limit do
          local following = lines[finish + 1]
          if following:match("^%s+%S") then
            finish = finish + 1
          elseif following:match("^%s*$") then
            local after = finish + 1
            while after < limit and lines[after + 1]:match("^%s*$") do
              after = after + 1
            end
            if after < limit and (lines[after + 1]:match("^    %s*%S") or lines[after + 1]:match("^\t")) then
              finish = after
            else
              break
            end
          else
            break
          end
        end
        block = {
          type = "footnote",
          id = line:match("^ ? ? ?%[%^([^%]]+)%]:"),
          label_end = #line:match("^ ? ? ?%[%^[^%]]+%]:"),
          text_col = #line:match("^ ? ? ?%[%^[^%]]+%]:%s*"),
          start_row = row,
          end_row = finish,
        }
      elseif line:match("^%s*%[[^%]]+%]:") then
        block = { type = "reference", start_row = row, end_row = row + 1 }
      elseif
        line:match("^ ? ? ?[%*%-_][%s%*%-_]+$")
        and #line:gsub("%s", "") >= 3
        and (line:gsub("[%s*]", "") == "" or line:gsub("[%s-]", "") == "" or line:gsub("[%s_]", "") == "")
      then
        block = { type = "rule", start_row = row, end_row = row + 1 }
      elseif line:match("^    ") and (row == 0 or lines[row]:match("^%s*$")) then
        local finish = row + 1
        while finish < limit and (lines[finish + 1]:match("^    ") or lines[finish + 1]:match("^%s*$")) do
          finish = finish + 1
        end
        block = {
          type = "code",
          start_row = row,
          end_row = finish,
          body_start = row,
          body_end = finish,
          language = "",
          indent = 4,
        }
      else
        local kind = line:match("^%s*>") and "quote"
          or (line:match("^%s*[-+*]%s+") or line:match("^%s*%d+[.)]%s+")) and "list"
          or "paragraph"
        block = { type = kind, start_row = row, end_row = row + 1 }
      end
    end
    result[#result + 1] = block
    row = math.max(row + 1, block.end_row)
  end
  return result
end
return M
