local M = {}
---@class MdReadableHeading
---@field id string Unique slug (GitHub style)
---@field title string Plain title without inline markup
---@field level integer 1-6
---@field start_row integer
---@field range MdReadableRange Heading rows
---@field sectionRange MdReadableRange Up to the next heading of the same or higher level
---@field children MdReadableHeading[]
---@field parent? string Parent heading id
--- Also links each heading block to its entry through `block.heading`.
---@param blocks MdReadableBlock[]
---@param lines string[]
---@return MdReadableHeading[]
function M.build(blocks, lines)
  local result, stack, seen = {}, {}, {}
  for _, block in ipairs(blocks) do
    if block.type == "heading" then
      local title = block.text
        :gsub("!?(%b[])%b()", function(s)
          return s:sub(2, -2)
        end)
        :gsub("[*_`~]", "")
      local slug = vim.fn.tolower(title):gsub("[^%w%s_\128-\255-]", ""):gsub("%s", "-")
      local base = slug
      seen[base] = (seen[base] or 0) + 1
      if seen[base] > 1 then
        slug = base .. "-" .. (seen[base] - 1)
      end
      local heading = {
        id = slug,
        title = title,
        level = block.level,
        start_row = block.start_row,
        range = { start = { row = block.start_row, byteColumn = 0 }, ["end"] = { row = block.end_row, byteColumn = 0 } },
        sectionRange = { start = { row = block.start_row, byteColumn = 0 }, ["end"] = { row = #lines, byteColumn = 0 } },
        children = {},
      }
      while #stack > 0 and stack[#stack].level >= heading.level do
        stack[#stack].sectionRange["end"] = { row = block.start_row, byteColumn = 0 }
        table.remove(stack)
      end
      if #stack > 0 then
        heading.parent = stack[#stack].id
        table.insert(stack[#stack].children, heading)
      end
      result[#result + 1], stack[#stack + 1] = heading, heading
      block.heading = heading
    end
  end
  return result
end
return M
