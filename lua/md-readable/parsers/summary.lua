local M = {}
---@class MdReadableParseSummaryItem
---@field kind "heading"|"link"|"text"
---@field title string
---@field children MdReadableParseSummaryItem[]
---@field level? integer heading
---@field first? boolean heading: appears before any other content
---@field target? string link
---@field link_title? string link: quoted title
---@field numbered? boolean
---@field source? MdReadableNavSource
---@param input string|string[]
---@param path string For sources and diagnostics
---@return MdReadableParseSummaryItem[]
---@return MdReadableNavDiagnostic[]
function M.parse(input, path)
  local lines = type(input) == "string" and vim.split(input, "\n", { plain = true }) or input --[[@as string[] ]]
  local items, diagnostics, stack = {}, {}, {}
  local saw_content = false
  for i, line in ipairs(lines or {}) do
    local indent, body = line:match("^(%s*)(.*)$")
    local level, heading = body:match("^(#+)%s+(.+)$")
    local list_body = body:match("^[-*+]%s+(.*)$") or body:match("^%d+[.)]%s+(.*)$")
    local text = list_body or body
    local title, raw = text:match("^%[(.-)%]%((.*)%)%s*$")
    local node
    if level then
      node = { kind = "heading", title = heading, level = #level, children = {}, first = not saw_content }
      stack = {}
    elseif title then
      local target, link_title = raw:match('^(.-)%s+"(.-)"%s*$')
      raw = vim.trim(target or raw)
      if raw:sub(1, 1) == "<" and raw:sub(-1) == ">" then
        raw = raw:sub(2, -2)
      end
      node = {
        kind = "link",
        title = title,
        target = raw,
        link_title = link_title,
        children = {},
        numbered = list_body ~= nil,
      }
    elseif list_body then
      node = { kind = "text", title = list_body, children = {}, numbered = true }
    elseif body ~= "" and not body:match("^%-%-%-+$") then
      diagnostics[#diagnostics + 1] = {
        severity = "warning",
        code = "summary-syntax",
        message = "Unsupported SUMMARY line",
        source = { path = path, row = i - 1 },
      }
    end
    if node then
      node.source = { path = path, row = i - 1, byteColumn = #indent }
      local depth = #indent:gsub("\t", "    ")
      if list_body then
        while #stack > 0 and stack[#stack].indent >= depth do
          table.remove(stack)
        end
        local parent = stack[#stack]
        table.insert(parent and parent.node.children or items, node)
        stack[#stack + 1] = { node = node, indent = depth }
      else
        table.insert(items, node)
        stack = {}
      end
      saw_content = true
    end
  end
  return items, diagnostics
end
return M
