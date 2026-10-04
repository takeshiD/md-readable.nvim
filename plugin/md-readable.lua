if vim.g.loaded_md_readable then
  return
end
vim.g.loaded_md_readable = true
vim.api.nvim_create_user_command("MdReadable", function(opts)
  require("md-readable").command(opts)
end, {
  nargs = "*",
  range = true,
  desc = "Read Markdown with source-aware navigation",
  ---@param lead string
  ---@param line string
  ---@param cursor integer
  ---@return string[]
  complete = function(lead, line, cursor)
    return require("md-readable").complete(lead, line, cursor)
  end,
})
