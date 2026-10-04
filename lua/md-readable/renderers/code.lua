local M = {}
local aliases = { js = "javascript", ts = "typescript", sh = "bash", yml = "yaml", py = "python", rs = "rust" }
-- Filetype of a fence language: aliases and file extensions ("py") included.
---@param language string
---@return string
function M.filetype(language)
  return aliases[language] or vim.filetype.match({ filename = "code." .. language }) or language:lower()
end
-- Language icon from the chosen provider; nil when it is not installed or
-- has no icon. The fence language is tried as a filetype, then as an extension.
---@param language string
---@param provider "mini"|"web-devicons"
---@return string? icon
---@return string? group Highlight group of the icon
function M.icon(language, provider)
  if language == "" then
    return nil
  end
  local filetype = M.filetype(language)
  if provider == "mini" then
    local ok, mini = pcall(require, "mini.icons")
    if not ok then
      return nil
    end
    for _, query in ipairs({ { "filetype", filetype }, { "extension", language } }) do
      local found, icon, group, is_default = pcall(mini.get, query[1], query[2])
      if found and icon and not is_default then
        return icon, group
      end
    end
  elseif provider == "web-devicons" then
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if not ok then
      return nil
    end
    local icon, group = devicons.get_icon_by_filetype(filetype, { default = false })
    if not icon then
      icon, group = devicons.get_icon("code." .. language, language, { default = false })
    end
    return icon, group
  end
end
-- The UI can also inspect code_blocks to attach a language-specific highlighter.
-- A missing parser/query simply leaves the code's plain-text highlight in place.
-- With a code palette (code.theme / code.colors), captures map to its roles.
---@param lines string[] Code body
---@param language string Fence language ("" for none)
---@param code? MdReadableUserConfigCode
---@return MdReadableRenderedHighlight[] highlights Rows relative to the body
function M.highlights(lines, language, code)
  if language == "" or not vim.treesitter then
    return {}
  end
  local lang = aliases[language] or language
  local code_theme = require("md-readable.ui.code_theme")
  local palette = code_theme.palette(code)
  ---@param capture string
  ---@return string?
  local function group(capture)
    if not palette then
      return "@" .. capture .. "." .. lang
    end
    local role = code_theme.role(capture)
    if role and palette[role] then
      return code_theme.group(role)
    end
    -- A preset colors everything it knows; with user colors only, the rest
    -- keeps the colorscheme.
    return not (code and code.theme) and ("@" .. capture .. "." .. lang) or nil
  end
  local ok, result = pcall(function()
    local source = table.concat(lines, "\n")
    local parser = vim.treesitter.get_string_parser(source, lang)
    local query = vim.treesitter.query.get(lang, "highlights")
    if not query then
      return {}
    end
    local highlights = {}
    ---@diagnostic disable-next-line: param-type-mismatch
    for _, tree in ipairs(parser:parse()) do
      for id, node in query:iter_captures(tree:root(), source, 0, #lines) do
        local name = group(query.captures[id])
        local sr, sc, er, ec = node:range()
        for row = sr, er do
          if name and lines[row + 1] then
            highlights[#highlights + 1] = {
              row = row,
              start_col = row == sr and sc or 0,
              end_col = row == er and ec or #lines[row + 1],
              group = name,
            }
          end
        end
      end
    end
    return highlights
  end)
  return ok and result or {}
end
return M
