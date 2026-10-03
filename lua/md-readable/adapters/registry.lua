local M = {}
M.entries = {
  { id = "mdbook", files = { "book.toml" } },
  { id = "honkit", files = { "book.json", "book.js" } },
  { id = "gitbook", files = { "gitbook-docs.yaml", ".gitbook.yaml" } },
  { id = "mkdocs", files = { "mkdocs.yml", "mkdocs.yaml" } },
  { id = "zensical", files = { "zensical.toml", "mkdocs.yml", "mkdocs.yaml" } },
  { id = "docusaurus", files = { "docusaurus.config.ts", "docusaurus.config.js", "docusaurus.config.mjs" } },
  { id = "astro", files = { "astro.config.mjs", "astro.config.ts", "astro.config.js" } },
}
function M.get(id)
  for _, entry in ipairs(M.entries) do
    if entry.id == id then
      return require("md-readable.adapters." .. id)
    end
  end
end
return M
