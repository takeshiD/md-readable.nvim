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
  complete = function(lead)
    return require("md-readable").complete(lead)
  end,
})
