local M = {}
---@alias MdReadableRenderPieceKind 'text'|'node'|'omission'
--- A run of display text; source columns are absolute bytes in the source line.
---@class MdReadableRenderPiece
---@field text string
---@field group? string Highlight group
---@field kind? MdReadableRenderPieceKind Defaults to 'text'
---@field source_start? integer Absent for decoration
---@field source_end? integer Exclusive
---@field source_row? integer Overrides the emitted row's source row (joined prose)
---@field full_start? integer Entire source element start (links / omitted cells)
---@field full_end? integer
---@field node_complete? boolean False for a truncated label fragment
---@alias MdReadableLinkIconSet table<MdReadableLinkKind, string>
---@param text string
---@param a integer
---@param b integer
---@param group? string
---@param kind? MdReadableRenderPieceKind
---@return MdReadableRenderPiece
local function piece(text, a, b, group, kind)
  return { text = text, source_start = a, source_end = b, group = group, kind = kind or "text" }
end
--- UTF-8 character starting at byte `i` (1-based).
---@param text string
---@param i integer
---@return string
local function char_at(text, i)
  return text:match("^[%z\1-\127\194-\244][\128-\191]*", i) or text:sub(i, i)
end
M.char_at = char_at

-- Link kind markers appended after labelled links. No Nerd Font is needed.
---@type table<string, MdReadableLinkIconSet>
M.icon_sets = {
  unicode = { external = "↗", document = "→", anchor = "#", asset = "⧉" },
  ascii = { external = "^", document = ">", anchor = "#", asset = "*" },
}
---@param opts MdReadableRenderOptions
---@param kind MdReadableLinkKind
---@return string?
function M.icon(opts, kind)
  if (opts.links or {}).enable == false then
    return nil
  end
  local setting = (opts.links or {}).icons
  local set = type(setting) == "table" and vim.tbl_extend("force", M.icon_sets.unicode, setting) or M.icon_sets[setting]
  return set and set[kind] or nil
end

-- Pieces use absolute source byte columns; decoration has no source columns.
---@param line string
---@param row integer 0-based source row
---@param links? MdReadableLink[]
---@param opts? MdReadableRenderOptions
---@param start_col? integer 0-based; defaults to 0
---@param end_col? integer Exclusive; defaults to #line
---@return MdReadableRenderPiece[]
function M.parse(line, row, links, opts, start_col, end_col)
  opts, start_col, end_col = opts or {}, start_col or 0, end_col or #line
  -- links.enable = false keeps labels as plain text: no link highlight or marker.
  local link_group = (opts.links or {}).enable ~= false and "MdReadableLink" or nil
  local by_start = {}
  for _, link in ipairs(links or {}) do
    if link.range.start.row == row then
      by_start[link.range.start.byteColumn + 1] = link
    end
  end
  local result = {}
  ---@param item MdReadableRenderPiece
  local function add(item)
    local previous = result[#result]
    if
      previous
      and previous.kind == "text"
      and item.kind == "text"
      and previous.group == item.group
      and previous.source_end == item.source_start
      and #previous.text == previous.source_end - previous.source_start
      and #item.text == item.source_end - item.source_start
    then
      previous.text, previous.source_end = previous.text .. item.text, item.source_end
    else
      result[#result + 1] = item
    end
  end
  ---@type fun(first:integer, last:integer, group?:string)
  local parse
  ---@param first integer 1-based
  ---@param last integer 1-based, inclusive
  ---@param group? string
  parse = function(first, last, group)
    local i = first
    while i <= last do
      local c, link = line:sub(i, i), by_start[i]
      if link and link.range["end"].byteColumn <= last then
        if link.kind == "footnote" then
          -- Every displayed character maps to the whole [^id] reference.
          add(piece("[" .. link.text .. "]", i - 1, link.range["end"].byteColumn, "MdReadableFootnote"))
        elseif link.kind == "unresolved" then
          add(piece(line:sub(i, link.range["end"].byteColumn), i - 1, link.range["end"].byteColumn, "MdReadableMuted"))
        elseif link.kind == "image" then
          local item =
            piece(link.text ~= "" and link.text or "Image", link.label_start, link.label_end, link_group, "node")
          item.full_start, item.full_end = link.range.start.byteColumn, link.range["end"].byteColumn
          add({ text = "[Image: " })
          add(item)
          add({ text = "]" })
        else
          local item = piece(link.text, link.label_start, link.label_end, link_group, "node")
          item.full_start, item.full_end = link.range.start.byteColumn, link.range["end"].byteColumn
          local max_url = opts.max_url_width or 48
          if (link.style == "bare" or link.style == "autolink") and vim.fn.strdisplaywidth(item.text) > max_url then
            local text = ""
            for char in item.text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
              if vim.fn.strdisplaywidth(text .. char) > max_url - 1 then
                break
              end
              text = text .. char
            end
            item.text, item.source_end = text, item.source_start + #text
            item.node_complete = false
            add(item)
            local omission = piece("…", item.source_end, link.label_end, "MdReadableOmission", "omission")
            omission.full_start, omission.full_end = link.range.start.byteColumn, link.range["end"].byteColumn
            add(omission)
          else
            local before = #result
            by_start[i] = nil
            parse(link.label_start + 1, link.label_end, link_group)
            by_start[i] = link
            for index = before + 1, #result do
              local label = result[index]
              label.kind, label.full_start, label.full_end = "node", item.full_start, item.full_end
            end
            local icon = link.style ~= "bare" and link.style ~= "autolink" and M.icon(opts, link.kind)
            if icon then
              add({ text = icon, group = "MdReadableLinkIcon" }) -- Decoration: no source range.
            end
          end
        end
        i = link.range["end"].byteColumn + 1
      elseif c == "&" then
        local entity = line:match("^&([#%w]+);", i)
        local named = {
          amp = "&",
          lt = "<",
          gt = ">",
          quot = '"',
          apos = "'",
          nbsp = " ",
          copy = "©",
          reg = "®",
          hellip = "…",
          mdash = "—",
          ndash = "–",
        }
        local decoded = entity and named[entity]
        local number = entity
          and (
            entity:match("^#(%d+)$") and tonumber(entity:sub(2))
            or entity:match("^#[xX]%x+$") and tonumber(entity:sub(3), 16)
          )
        if number and number > 0 and number <= 1114111 and not (number >= 55296 and number <= 57343) then
          decoded = vim.fn.nr2char(number)
        end
        if decoded and i + #entity + 1 <= last then
          add(piece(decoded, i - 1, i + #entity + 1, group))
          i = i + #entity + 2
        else
          add(piece(c, i - 1, i, group))
          i = i + 1
        end
      elseif c == "\\" and i < last and line:sub(i + 1, i + 1):match("%p") then
        add(piece(line:sub(i + 1, i + 1), i - 1, i + 1, group))
        i = i + 2
      elseif c == "`" then
        local ticks = line:match("^`+", i)
        local finish = line:find(ticks, i + #ticks, true)
        if finish and finish + #ticks - 1 <= last then
          local first_content, end_content = i + #ticks, finish - 1
          local content = line:sub(first_content, end_content)
          if content:match("^ .+ $") and content:match("[^ ]") then
            first_content, end_content = first_content + 1, end_content - 1
          end
          add(piece(line:sub(first_content, end_content), first_content - 1, end_content, "MdReadableCode"))
          i = finish + #ticks
        else
          add(piece(ticks, i - 1, i + #ticks - 1, group))
          i = i + #ticks
        end
      elseif c == "*" or c == "_" or line:sub(i, i + 1) == "~~" then
        local run = c == "~" and "~~" or line:match(c == "*" and "^%*+" or "^_+", i)
        local marker = #run >= 2 and run:sub(1, 2) or run
        if #run >= 3 and c ~= "~" then
          marker = run:sub(1, 3)
        end
        local finish = line:find(marker, i + #marker, true)
        local prev, next_char = line:sub(i - 1, i - 1), line:sub(i + #marker, i + #marker)
        if
          finish
          and finish + #marker - 1 <= last
          and not next_char:match("%s")
          and next_char ~= ""
          and not line:sub(finish - 1, finish - 1):match("%s")
          and not (c == "_" and prev:match("[%w\128-\255]") and next_char:match("[%w\128-\255]"))
        then
          parse(
            i + #marker,
            finish - 1,
            c == "~" and "MdReadableStrike" or #marker >= 2 and "MdReadableBold" or "MdReadableItalic"
          )
          i = finish + #marker
        else
          add(piece(run, i - 1, i + #run - 1, group))
          i = i + #run
        end
      else
        local char = char_at(line, i)
        add(piece(char, i - 1, i + #char - 1, group))
        i = i + #char
      end
    end
  end
  parse(start_col + 1, end_col)
  return result
end
return M
