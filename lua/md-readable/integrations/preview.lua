local M = {}
local uv = vim.uv or vim.loop
local next_id = 0
local images = { png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true, avif = true, bmp = true }
---@alias MdReadablePreviewKind "markdown"|"image"
---@class MdReadablePreviewOptions
---@field config? MdReadableConfig Defaults to the current plugin options
---@field max_lines? integer
---@field max_bytes? integer
---@field debounce? integer Milliseconds
---@field on_render? fun(session:MdReadablePreviewSession)
---@class MdReadablePreviewSession Minimal session for one rendered preview
---@field id string
---@field source_buf integer Scratch buffer holding the previewed lines
---@field read_buf integer
---@field read_win integer
---@field document MdReadableDocument
---@field rendered MdReadableRendered
---@field config MdReadableConfig
---@field generation integer
---@field closed boolean
---@param path? string
---@return MdReadablePreviewKind?
function M.kind(path)
  if type(path) ~= "string" then
    return nil
  end
  local extension = path:lower():match("%.([%w]+)$")
  if extension == "md" or extension == "markdown" or extension == "mdx" then
    return "markdown"
  end
  return images[extension] and "image" or nil
end
---@return table? media Image provider module
local function provider()
  local ok, value = pcall(require, "md-readable.providers.image")
  return ok and value or nil
end
---@param opts MdReadablePreviewOptions
---@return MdReadableConfig
local function config(opts)
  local ok, module = pcall(require, "md-readable.config")
  if opts.config then
    local value = vim.deepcopy(opts.config --[[@as MdReadableConfig]])
    return ok and module.normalize(value) or value
  end
  return ok and module.get() or { images = { enable = false }, table = { max_cell_width = 28 } }
end
---@param media? table
---@param configuration MdReadableConfig
---@return boolean
local function capable(media, configuration)
  if not media or (configuration.images or {}).enable == false then
    return false
  end
  local ok, value = pcall(media.capabilities)
  if not ok then
    return false
  end
  if type(value) == "table" then
    return value.supported == true or value.available == true or value.enabled == true
  end
  return value == true
end
---@param opts? MdReadablePreviewOptions
---@return boolean
M.capable = function(opts)
  return capable(provider(), config(opts or {}))
end

---@param opts? MdReadablePreviewOptions
---@return MdReadablePreviewEngine
function M.new(opts)
  opts = opts or {}
  next_id = next_id + 1
  ---@class MdReadablePreviewEngine
  ---@field generation integer Bumped on every clear; stale callbacks compare it
  ---@field closed boolean
  ---@field id string
  ---@field ns integer
  ---@field timer? uv.uv_timer_t Debounce timer
  ---@field session? MdReadablePreviewSession
  local self = {
    generation = 0,
    closed = false,
    id = "preview-" .. next_id,
    ns = vim.api.nvim_create_namespace("md-readable-preview-" .. next_id),
  }
  local cleanup_id
  function self:clear()
    self.generation = self.generation + 1
    if self.timer then
      self.timer:stop()
      if not self.timer:is_closing() then
        self.timer:close()
      end
      self.timer = nil
    end
    if self.session then
      self.session.closed = true
      local media = provider()
      if media then
        pcall(media.close, self.session)
      end
      if self.session.source_buf and vim.api.nvim_buf_is_valid(self.session.source_buf) then
        pcall(vim.api.nvim_buf_delete, self.session.source_buf, { force = true })
      end
      self.session = nil
    end
  end
  function self:close()
    self:clear()
    self.closed = true
    if cleanup_id then
      pcall(vim.api.nvim_del_autocmd, cleanup_id)
      cleanup_id = nil
    end
  end
  ---@param path? string
  ---@param buf integer Preview buffer
  ---@param win integer Preview window
  ---@param position? integer[] {1-based row, 0-based byte column} in the source
  ---@param fallback? fun() Shows the picker's default preview
  ---@return boolean handled
  function self:show(path, buf, win, position, fallback)
    self:clear()
    self.closed = false
    local generation, kind = self.generation, M.kind(path)
    local configuration, media = config(opts), provider()
    local media_enabled = capable(media, configuration)
    ---@return boolean
    local function current()
      return not self.closed
        and self.generation == generation
        and vim.api.nvim_buf_is_valid(buf)
        and vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_win_get_buf(win) == buf
    end
    local function fail()
      vim.schedule(function()
        if current() and fallback then
          fallback()
        end
      end)
    end
    if not kind or (kind == "image" and not media_enabled) then
      if fallback then
        fallback()
      end
      return false
    end
    ---@cast path -nil
    if cleanup_id then
      pcall(vim.api.nvim_del_autocmd, cleanup_id)
    end
    cleanup_id = vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        cleanup_id = nil
        self:close()
      end,
    })
    ---@param lines string[]
    local function apply(lines)
      if not current() then
        return
      end
      if #lines > (opts.max_lines or 2000) then
        fail()
        return
      end
      local width = math.max(1, vim.api.nvim_win_get_width(win) - 2)
      local document = require("md-readable.document.parser").parse(lines, { path = path })
      local rendered = require("md-readable.reader.render").render(document, {
        width = width,
        table = configuration.table,
        links = configuration.links,
        media = { enabled = media_enabled, image_height = (configuration.images or {}).height or 8 },
      })
      if not current() then
        return
      end
      local source_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, lines)
      document.bufnr = source_buf
      self.session = {
        id = self.id,
        source_buf = source_buf,
        read_buf = buf,
        read_win = win,
        document = document,
        rendered = rendered,
        config = configuration,
        generation = generation,
        closed = false,
      }
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered.lines)
      vim.api.nvim_buf_clear_namespace(buf, self.ns, 0, -1)
      local ok_theme, theme = pcall(require, "md-readable.ui.theme")
      if ok_theme then
        pcall(theme.setup)
      end
      for _, highlight in ipairs(rendered.highlights) do
        pcall(vim.api.nvim_buf_set_extmark, buf, self.ns, highlight.row, highlight.start_col, {
          end_col = highlight.end_col,
          hl_group = highlight.group,
          priority = 110,
        })
      end
      vim.bo[buf].modifiable = false
      local target_source = math.max(0, (position and position[1] or 1) - 1)
      local target, column = #rendered.lines, 0
      local source_column = math.max(0, position and position[2] or 0)
      for row, source in ipairs(rendered.row_map) do
        if source >= target_source then
          target = row
          break
        end
      end
      for _, segment in ipairs(rendered.segments) do
        if segment.source_row == target_source then
          target, column = segment.row + 1, segment.start_col
          if source_column < segment.source_end then
            column =
              math.min(segment.end_col - 1, segment.start_col + math.max(0, source_column - segment.source_start))
            break
          end
        end
      end
      vim.api.nvim_win_set_cursor(win, { math.max(1, target), column })
      vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zz")
      end)
      if media_enabled then
        ---@cast media -nil
        local session = self.session
        vim.schedule(function()
          if current() and self.session == session then
            pcall(media.update, session)
          end
        end)
      end
      if opts.on_render then
        opts.on_render(self.session)
      end
    end
    local function load()
      if not current() then
        return
      end
      if kind == "image" then
        -- Inline Markdown supplies the same metadata as a document image.
        apply({
          "![" .. vim.fn.fnamemodify(path, ":t"):gsub("([\\%]])", "\\%1") .. "](<" .. path:gsub(">", "%%3E") .. ">)",
        })
        return
      end
      local loaded = vim.fn.bufnr(path)
      if loaded > 0 and vim.api.nvim_buf_is_loaded(loaded) then
        apply(vim.api.nvim_buf_get_lines(loaded, 0, -1, false))
        return
      end
      uv.fs_open(path, "r", 438, function(open_error, fd)
        if open_error or not fd then
          fail()
          return
        end
        uv.fs_fstat(fd, function(stat_error, stat)
          if
            stat_error
            or not stat
            or stat.type ~= "file"
            ---@diagnostic disable-next-line: ambiguity-1
            or stat.size > (opts.max_bytes or 1024 * 1024)
            or self.generation ~= generation
          then
            uv.fs_close(fd)
            fail()
            return
          end
          uv.fs_read(fd, stat.size, 0, function(read_error, data)
            uv.fs_close(fd)
            if read_error or not data then
              fail()
              return
            end
            vim.schedule(function()
              if not current() then
                return
              end
              if data:find("\0", 1, true) then
                fail()
                return
              end
              local lines = vim.split(data:gsub("\r\n", "\n"), "\n", { plain = true })
              if lines[#lines] == "" and #lines > 1 then
                table.remove(lines)
              end
              apply(lines)
            end)
          end)
        end)
      end)
    end
    self.timer = vim.defer_fn(function()
      self.timer = nil
      load()
    end, opts.debounce or 35)
    return true
  end
  return self
end
return M
