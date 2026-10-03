local M = {}
-- A fresh previewer owns its cancellation/cleanup state. Requiring this module
-- does not require Telescope; only explicitly constructing a previewer does.
function M.previewer(opts)
  opts = opts or {}
  local engine = require("md-readable.integrations.preview").new(opts)
  return require("telescope.previewers").new_buffer_previewer({
    title = "Markdown Preview",
    define_preview = function(self, entry)
      local path = entry.path or entry.filename or (type(entry.value) == "string" and entry.value or nil)
      local buf, win = self.state.bufnr, self.state.winid
      local position = { entry.lnum or 1, (entry.col or 1) - 1 }
      engine:show(path, buf, win, position, function()
        if not path then return end
        require("telescope.config").values.buffer_previewer_maker(path, buf, {
          bufname = self.state.bufname, winid = win,
          callback = function()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
              local row = math.max(1, math.min(position[1], vim.api.nvim_buf_line_count(buf)))
              pcall(vim.api.nvim_win_set_cursor, win, { row, math.max(0, position[2]) })
            end
          end,
        })
      end)
    end,
    teardown = function() engine:close() end,
  })
end
function M.picker(name, opts)
  local picker = require("telescope.builtin")[name]
  assert(type(picker) == "function", "Unknown Telescope picker: " .. tostring(name))
  opts = vim.tbl_extend("force", {}, opts or {}, { previewer = M.previewer() })
  return picker(opts)
end
return M
