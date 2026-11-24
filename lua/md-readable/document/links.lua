local M = {}
---@alias MdReadableLinkKind 'footnote'|'image'|'unresolved'|'anchor'|'external'|'asset'|'document'
---@alias MdReadableLinkStyle 'inline'|'reference'|'footnote'|'autolink'|'bare'|'html'
---@class MdReadableLink
---@field text string Label text as written
---@field target string Unescaped target; footnotes use "^id"
---@field kind MdReadableLinkKind
---@field range MdReadableRange Whole link source
---@field label_start integer Label start byte (0-based)
---@field label_end integer Label end byte (exclusive)
---@field style MdReadableLinkStyle
---@field definition_row? integer Footnote definition row (footnotes only)
---@class MdReadableReference
---@field row integer Definition row (0-based)
---@field target? string Link reference definitions only
---@field footnote? boolean
---@field id? string Footnote id as written
---@param value string
---@return string
local function normalize(value)
  return value:lower():gsub("%s+", " "):match("^%s*(.-)%s*$")
end
---@param value string
---@return string
local function unescape(value)
  return (value:gsub("\\([%p])", "%1"))
end
---@param row integer
---@param a integer
---@param b integer
---@return MdReadableRange
local function range(row, a, b)
  return { start = { row = row, byteColumn = a }, ["end"] = { row = row, byteColumn = b } }
end

--- Keys are normalized labels; footnote definitions are keyed "^" .. id.
---@param lines string[]
---@return table<string, MdReadableReference>
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

--- Index of the bracket closing the one at `start` (1-based), skipping escapes.
---@param text string
---@param start integer
---@param opening string
---@param ending string
---@return integer?
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

-- Inline HTML that GitHub renders in Markdown: <a href>label</a> and <img src alt>.
-- range covers the whole tag(s); the label is the <a> content or the alt value.
local function attribute(tag, tag_start, name)
  for _, quote in ipairs({ '"', "'" }) do
    local _, e, value = tag:find("[%s/]" .. name .. "%s*=%s*" .. quote .. "([^" .. quote .. "]*)" .. quote)
    if e then
      local value_start = tag_start + e - #value - 1 -- 1-based first byte of the value
      return value, value_start, value_start + #value - 1
    end
  end
  local _, e, value = tag:find("[%s/]" .. name .. "%s*=%s*([^%s\"'=<>`]+)")
  if e then
    return value, tag_start + e - #value, tag_start + e - 1
  end
end
local function decode(value)
  return (value:gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"))
end
function M.html(line, i, row)
  local tag = line:match("^<[aA]%s[^<>]*>", i) or line:match("^<[iI][mM][gG][%s/][^<>]*>", i)
  if not tag then
    return nil
  end
  local tag_end = i + #tag - 1
  if tag:sub(2, 2):lower() == "a" then
    local href = attribute(tag, i, "href")
    local close_start, close_end = line:find("</[aA]%s*>", tag_end + 1)
    if not href or not close_start then
      return nil
    end
    href = decode(href)
    return {
      text = line:sub(tag_end + 1, close_start - 1),
      target = href,
      kind = href:match("^#") and "anchor"
        or href:match("^[%a][%w+.-]*:") and "external"
        or href:match("%.[%w]+$") and not href:lower():match("%.mdx?$") and "asset"
        or "document",
      range = range(row, i - 1, close_end),
      label_start = tag_end,
      label_end = close_start - 1,
      style = "html",
    }
  end
  local src = attribute(tag, i, "src")
  if not src then
    return nil
  end
  local alt, alt_start, alt_end = attribute(tag, i, "alt")
  if not alt or alt == "" then
    alt_start, alt_end = i, tag_end
  end
  return {
    text = alt and decode(alt) or "",
    target = decode(src),
    kind = "image",
    range = range(row, i - 1, tag_end),
    label_start = alt_start - 1,
    label_end = alt_end,
    style = "html",
  }
end

---@param line string
---@param row integer 0-based
---@param references? table<string, MdReadableReference>
---@return MdReadableLink[]
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
      ---@type string|false|nil
      local footnote = not image and close and line:sub(a + 1, close - 1):match("^%^(%S+)$")
      if footnote then
        local after = line:sub(close + 1, close + 1)
        local ref = references["^" .. normalize(footnote)]
        if after == ":" and line:sub(1, i - 1):match("^ ? ? ?$") then
          i = close + 1 -- Definition label; rendered by the footnote block.
        elseif ref and ref.footnote and after ~= "(" and after ~= "[" then
          ---@cast close integer
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
          ---@cast finish integer
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
        local html = M.html(line, i, row)
        if html then
          result[#result + 1] = html
          i = html.range["end"].byteColumn + 1
        elseif value and (value:match("^[%a][%w+.-]*:") or value:match("^[^@]+@[^@]+%.[^@]+$")) then
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
