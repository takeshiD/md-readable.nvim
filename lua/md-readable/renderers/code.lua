local M = {}
-- The UI can also inspect code_blocks to attach a language-specific highlighter.
-- A missing parser/query simply leaves the code's plain-text highlight in place.
function M.highlights(lines, language)
  if language == "" or not vim.treesitter then return {} end
  local lang = ({ js = "javascript", ts = "typescript", sh = "bash", yml = "yaml", py = "python", rs = "rust" })[language] or language
  local ok, result = pcall(function()
    local source = table.concat(lines, "\n")
    local parser = vim.treesitter.get_string_parser(source, lang)
    local query = vim.treesitter.query.get(lang, "highlights")
    if not query then return {} end
    local highlights = {}
    for _, tree in ipairs(parser:parse()) do
      for id, node in query:iter_captures(tree:root(), source, 0, #lines) do
        local sr, sc, er, ec = node:range()
        for row = sr, er do
          if lines[row + 1] then highlights[#highlights + 1] = { row = row, start_col = row == sr and sc or 0,
            end_col = row == er and ec or #lines[row + 1], group = "@" .. query.captures[id] .. "." .. lang } end
        end
      end
    end
    return highlights
  end)
  return ok and result or {}
end
return M
