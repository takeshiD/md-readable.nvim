local M = {}
local function normalize(value)
  return value:lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
end
local function unescape(value)
  return (value:gsub("\\([%p])", "%1"))
end
local function range(row, a, b)
  return { start = { row = row, byteColumn = a }, ["end"] = { row = row, byteColumn = b } }
end

function M.references(lines)
  local result = {}
  for row, line in ipairs(lines) do
    local footnote = line:match("^ ? ? ?%[%^([^%]%s]+)%]:")
    local id, target = line:match("^%s*%[([^%]]+)%]:%s*<?([^%s>]+)>?")
    if footnote then
      result["^" .. normalize(footnote)] = { footnote = true, id = footnote, row = row - 1 }
    elseif id then
      result[normalize(id)] = { target = unescape(target), row = row - 1 }
    end
  end
  return result
end

local function closing(text, start, opening, ending)
  local depth, i = 1, start + 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" then
      i = i + 2
    else
      if c == opening then
        depth = depth + 1
      elseif c == ending then
        depth = depth - 1
      end
      if depth == 0 then
        return i
      end
      i = i + 1
    end
  end
end

function M.parse(line, row, references)
  references = references or {}
  local result, i = {}, 1
  while i <= #line do
    local c = line:sub(i, i)
    if c == "\\" then
      i = i + 2
    elseif c == "`" then
      local ticks = line:match("^`+", i)
      local finish = line:find(ticks, i + #ticks, true)
      i = finish and finish + #ticks or i + #ticks
    else
      local image = c == "!" and line:sub(i + 1, i + 1) == "["
      local a = image and i + 1 or i
      local close = line:sub(a, a) == "[" and closing(line, a, "[", "]")
      local target, finish, unresolved, style
      local footnote = not image and close and line:sub(a + 1, close - 1):match("^%^(%S+)$")
      if footnote then
        local after = line:sub(close + 1, close + 1)
        local ref = references["^" .. normalize(footnote)]
        if after == ":" and line:sub(1, i - 1):match("^ ? ? ?$") then
          i = close + 1 -- Definition label; rendered by the footnote block.
        elseif ref and ref.footnote and after ~= "(" and after ~= "[" then
          result[#result + 1] = {
            text = footnote,
            target = "^" .. footnote,
            kind = "footnote",
            range = range(row, i - 1, close),
            label_start = a,
            label_end = close - 1,
            style = "footnote",
            definition_row = ref.row,
          }
          i = close + 1
        else
          footnote = nil
        end
      end
      if footnote then -- Handled above.
      elseif close then
        local after = line:sub(close + 1, close + 1)
        if after == "(" then
          finish = closing(line, close + 1, "(", ")")
          if finish then
            local inner = line:sub(close + 2, finish - 1):match("^%s*(.-)%s*$")
            target = inner:match("^<([^>]*)>") or inner:match("^(.-)%s+[\"']") or inner
            style = "inline"
          end
        else
          local ref_end = after == "[" and closing(line, close + 1, "[", "]")
          local id = ref_end and line:sub(close + 2, ref_end - 1) or line:sub(a + 1, close - 1)
          if id == "" then
            id = line:sub(a + 1, close - 1)
          end
          local ref = references[normalize(id)]
          if ref or ref_end then
            target, unresolved, finish, style = ref and ref.target or id, not ref, ref_end or close, "reference"
          end
        end
        if target then
          target = unescape(target)
          local kind = image and "image"
            or unresolved and "unresolved"
            or target:match("^#") and "anchor"
            or target:match("^[%a][%w+.-]*:") and "external"
            or target:match("%.[%w]+$") and not target:lower():match("%.mdx?$") and "asset"
            or "document"
          result[#result + 1] = {
            text = line:sub(a + 1, close - 1),
            target = target,
            kind = kind,
            range = range(row, i - 1, finish),
            label_start = a,
            label_end = close - 1,
            style = style,
          }
          i = finish + 1
        else
          i = i + 1
        end
      elseif c == "<" then
        local value = line:match("^<([^<>%s]+)>", i)
        if value and (value:match("^[%a][%w+.-]*:") or value:match("^[^@]+@[^@]+%.[^@]+$")) then
          local target_value = value:match("^[%a][%w+.-]*:") and value or "mailto:" .. value
          result[#result + 1] = {
            text = value,
            target = target_value,
            kind = "external",
            range = range(row, i - 1, i + #value + 1),
            label_start = i,
            label_end = i + #value,
            style = "autolink",
          }
          i = i + #value + 2
        else
          i = i + 1
        end
      else
        local url = line:match("^https?://[^%s<>]+", i) or line:match("^www%.[^%s<>]+", i)
        if url then
          url = url:gsub("[.,;:!?]+$", "")
          while url:sub(-1) == ")" and select(2, url:gsub("%)", "")) > select(2, url:gsub("%(", "")) do
            url = url:sub(1, -2)
          end
          result[#result + 1] = {
            text = url,
            target = url:match("^www%.") and "https://" .. url or url,
            kind = "external",
            range = range(row, i - 1, i + #url - 1),
            label_start = i - 1,
            label_end = i + #url - 1,
            style = "bare",
          }
          i = i + #url
        else
          i = i + 1
        end
      end
    end
  end
  return result
end
return M
