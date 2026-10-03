local M = {}
function M.parse(lines, path)
  if lines[1] ~= '---' and lines[1] ~= '+++' then return {}, {}, 0 end
  local delimiter = lines[1]
  for i = 2, #lines do
    if lines[i] == delimiter then
      local text = {}; for j = 2, i - 1 do text[#text + 1] = lines[j] end
      local value, diagnostics = require('md-readable.parsers.' .. (delimiter == '---' and 'yaml' or 'toml')).parse(text, path)
      for _, d in ipairs(diagnostics) do d.source.row = d.source.row + 1 end
      return value, diagnostics, i
    end
  end
  return nil, { { severity = 'error', code = 'frontmatter-unclosed', message = 'Unclosed frontmatter', source = { path = path, row = 0 } } }, 0
end
return M
