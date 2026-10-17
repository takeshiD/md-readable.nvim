local M = {}
local cache = require("md-readable.image.cache")
local capabilities = require("md-readable.image.capabilities")
local convert = require("md-readable.image.convert")
local display = require("md-readable.image.display")
---@class MdReadableImageState
---@field cancel fun()[]
---@field epoch integer Bumped on each redraw; stale callbacks compare against it
---@field group? integer Autocommand group
---@field signature? string Inputs of the last redraw (not the scroll position)
---@field started? table<integer, true> Indexes of rendered.images already requested
---@class MdReadableImageProblem
---@field label string
---@field message string
---@type table<MdReadableSession, MdReadableImageState>
local states = setmetatable({}, { __mode = "k" })

---@return boolean supported
---@return string? reason
function M.capabilities()
  return capabilities.get()
end

---@param state MdReadableImageState
local function clear(state)
  for _, cancel in ipairs(state.cancel or {}) do
    pcall(cancel)
  end
  state.cancel = {}
end

---@param session MdReadableSession
---@param target string
---@return string? path Absolute path or URL
---@return boolean remote
---@return string? err
function M.resolve(session, target)
  if target:match("^https?://") then
    return target, true
  end
  if target:match("^[%a][%w+.-]*:") then
    return nil, false, "unsupported image scheme"
  end
  local path = vim.uri_decode(target:gsub("[?#].*$", ""))
  if path:sub(1, 1) == "/" then
    return vim.fs.normalize(path), false
  end
  local source = (session.document or {}).path or vim.api.nvim_buf_get_name(session.source_buf)
  return vim.fs.normalize(vim.fs.dirname(source ~= "" and source or vim.fn.getcwd() .. "/untitled.md") .. "/" .. path),
    false
end

-- Stable identity of a media item; local images include the file identity so
-- a fixed or replaced file is retried.
---@param session MdReadableSession
---@param descriptor MdReadableRenderedImage
---@return string
function M.key(session, descriptor)
  if descriptor.kind == "mermaid" then
    return "mermaid\0"
      .. (
        type(descriptor.code) == "table" and table.concat(descriptor.code --[[@as string[] ]], "\n")
        or descriptor.code
        or ""
      )
  end
  local path, remote = M.resolve(session, descriptor.path or "")
  return "image\0" .. tostring(path or descriptor.path) .. "\0" .. (path and not remote and cache.identity(path) or "")
end

---@param descriptor MdReadableRenderedImage
---@return string
local function label(descriptor)
  if descriptor.kind == "mermaid" then
    return "Mermaid diagram (line " .. ((descriptor.source_row or 0) + 1) .. ")"
  end
  return tostring(descriptor.path)
end

-- Box an image may fill, as in snacks.image: images.width/height fix it
-- (default: the body width and the window height), min_*/max_* bound it.
---@param session MdReadableSession
---@param descriptor MdReadableRenderedImage
---@return integer columns
---@return integer rows
function M.box(session, descriptor)
  local opts = session.config.images or {}
  local ok, window_rows = pcall(vim.api.nvim_win_get_height, session.read_win)
  ---@param value integer
  ---@param min? integer
  ---@param max? integer
  local function bound(value, min, max)
    return math.max(min or 1, math.min(value, max or value))
  end
  local columns = bound(opts.width or descriptor.width or 80, opts.min_width, opts.max_width)
  local rows = bound(opts.height or (ok and window_rows or 24), opts.min_height, opts.max_height)
  return math.max(1, math.min(columns, descriptor.width or columns)), math.max(1, rows)
end

-- Pixel size of a PNG file from its header, or nil.
---@param path string
---@return integer? width
---@return integer? height
local function png_size(path)
  local fd = vim.uv.fs_open(path, "r", 420)
  if not fd then
    return nil
  end
  local header = vim.uv.fs_read(fd, 24, 0)
  vim.uv.fs_close(fd)
  local width, height = display.dimensions(header or "")
  if width then
    return width, height --[[@as integer]]
  end
end

-- Rows an image takes: its pixel size fitted into M.box. Known after the
-- first display of a converted or downloaded image; a local PNG is read now.
---@param session MdReadableSession
---@param descriptor MdReadableRenderedImage
---@return integer?
function M.rows(session, descriptor)
  session.media_sizes = session.media_sizes or {}
  local key = M.key(session, descriptor)
  local size = session.media_sizes[key]
  if not size then
    local path, remote = M.resolve(session, descriptor.path or "")
    local width, height
    if path and not remote then
      width, height = png_size(path)
    end
    if not width then
      return nil
    end
    size = { width, height }
    session.media_sizes[key] = size
  end
  local columns, rows = M.box(session, descriptor)
  local _, fitted = display.fit(size[1], size[2], columns, rows)
  return fitted
end

-- Reason a descriptor cannot be drawn, known before starting any work.
---@param session MdReadableSession
---@param descriptor MdReadableRenderedImage
---@return string?
function M.unavailable(session, descriptor)
  if descriptor.kind == "mermaid" then
    return require("md-readable.providers.mermaid").unavailable(session, descriptor)
  end
  local path, remote, err = M.resolve(session, descriptor.path or "")
  if not path then
    return err
  end
  if remote then
    return not (session.config.images or {}).remote and "web images are denied; use :MdReadable images allow" or nil
  end
  local identity, missing = cache.identity(path)
  return not identity and missing --[[@as string]] or nil
end

-- Returns the render-time predicate deciding which media reserve rows.
-- Known failures (static or from an earlier attempt) reserve none.
---@param session MdReadableSession
---@return fun(descriptor:MdReadableRenderedImage):boolean|integer
function M.reserver(session)
  session.media_skipped = {}
  return function(descriptor)
    local key = M.key(session, descriptor)
    local failure = (session.media_failures or {})[key]
    local reason = failure and failure.message or M.unavailable(session, descriptor)
    if reason then
      session.media_skipped[key] = { label = label(descriptor), message = reason }
      return false
    end
    -- A generated diagram gets the rows that fit it to the body width, an
    -- image those of its own size within the image box.
    if descriptor.kind == "mermaid" then
      return require("md-readable.providers.mermaid").rows(session, descriptor) or true
    end
    return M.rows(session, descriptor) or true
  end
end

-- Records a failed attempt and re-renders so the item's rows are released.
---@param session MdReadableSession
---@param descriptor MdReadableRenderedImage
---@param err? string
local function fail(session, descriptor, err)
  session.media_failures = session.media_failures or {}
  local key = M.key(session, descriptor)
  if session.media_failures[key] then
    return
  end
  session.media_failures[key] = { label = label(descriptor), message = tostring(err or "rendering failed") }
  if (descriptor.height or 0) > 0 and session.refresh then
    vim.schedule(function()
      if not session.closed then
        session:refresh()
      end
    end)
  end
end

---@param session MdReadableSession
function M.forget(session)
  session.media_failures = nil
end

---@param session MdReadableSession
function M.update(session)
  local opts = session.config.images or {}
  if
    session.closed
    or opts.enable == false
    or not vim.api.nvim_win_is_valid(session.read_win)
    or not M.capabilities()
  then
    M.close(session)
    return
  end
  local state = states[session]
  if not state then
    state = { cancel = {}, epoch = 0 }
    states[session] = state
    state.group = vim.api.nvim_create_augroup("MdReadableImages" .. session.id, { clear = true })
    vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized" }, {
      group = state.group,
      callback = function(event)
        if event.event == "VimResized" then
          display.reset_cell_size() -- the font size may have changed
        end
        vim.schedule(function()
          if states[session] == state then
            M.update(session)
          end
        end)
      end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
      group = state.group,
      pattern = tostring(session.read_win),
      callback = function()
        M.close(session)
      end,
    })
  end
  local info = vim.fn.getwininfo(session.read_win)[1]
  if not info then
    return
  end
  -- Placeholders scroll with the text, so scrolling only adds newly visible
  -- media; anything else redraws all of them.
  local parts = {
    session.generation or 0,
    session.read_win,
    info.width,
    vim.inspect(opts),
    vim.inspect(session.config.mermaid or {}),
  }
  for _, descriptor in ipairs(session.rendered.images or {}) do
    parts[#parts + 1] = vim.inspect(descriptor)
    if descriptor.kind == "image" and descriptor.path then
      local path, remote = M.resolve(session, descriptor.path)
      if path and not remote then
        parts[#parts + 1] = cache.identity(path) or path
      end
    end
  end
  local signature = table.concat(parts, "\0")
  if state.signature ~= signature then
    state.signature, state.epoch, state.started = signature, state.epoch + 1, {}
    clear(state)
  end
  local epoch = state.epoch
  ---@return boolean
  local function fresh()
    return states[session] == state and state.epoch == epoch and not session.closed
  end
  for index, image in ipairs(session.rendered.images or {}) do
    local descriptor = vim.deepcopy(image)
    descriptor.height = descriptor.height or opts.height or 10
    descriptor.width = math.min(descriptor.width or info.width, opts.max_width or info.width)
    if descriptor.kind ~= "mermaid" then
      descriptor.width = (M.box(session, descriptor))
    end
    local visible = not state.started[index]
      and descriptor.height > 0
      and descriptor.row
      and descriptor.row < info.botline
      and descriptor.row + descriptor.height > info.topline - 1
    if visible then
      state.started[index] = true
      ---@param path? string
      ---@param err? string
      local function show(path, err)
        if not fresh() then
          return
        end
        if not path then
          fail(session, descriptor, err)
          return
        end
        local cancel_conversion = convert.ensure(path, opts, function(png, conversion_err)
          if not fresh() then
            return
          end
          if not png then
            fail(session, descriptor, conversion_err)
            return
          end
          -- A converted or downloaded image is measured now: re-render once
          -- so it gets the rows of its own size.
          local key = descriptor.kind ~= "mermaid" and M.key(session, descriptor)
          if key and not (session.media_sizes or {})[key] then
            local width, height = png_size(png)
            if width then
              session.media_sizes = session.media_sizes or {}
              session.media_sizes[key] = { width, height }
              if M.rows(session, image) ~= image.height and session.refresh then
                vim.schedule(function()
                  if not session.closed then
                    session:refresh()
                  end
                end)
                return
              end
            end
          end
          local _, cancel_display = display.show(png, session.read_win, descriptor, opts, function(_, display_err)
            if fresh() and display_err then
              fail(session, descriptor, display_err)
            end
          end)
          state.cancel[#state.cancel + 1] = cancel_display
        end)
        state.cancel[#state.cancel + 1] = cancel_conversion
      end
      if descriptor.kind == "mermaid" then
        local mermaid = require("md-readable.providers.mermaid")
        state.cancel[#state.cancel + 1] = mermaid.render(session, descriptor, function(path, err)
          -- First generation: re-render once so the diagram gets its own rows.
          local rows = path and mermaid.rows(session, image)
          if rows and rows ~= image.height and fresh() then
            vim.schedule(function()
              if not session.closed then
                session:refresh()
              end
            end)
            return
          end
          show(path, err)
        end)
      elseif descriptor.path then
        local path, remote, err = M.resolve(session, descriptor.path)
        if not path then
          show(nil, err)
        elseif remote then
          state.cancel[#state.cancel + 1] = require("md-readable.image.download").fetch(path, opts, show)
        else
          show(path)
        end
      end
    end
  end
end

-- Media problems as "label: message", from this render and earlier attempts.
---@param session MdReadableSession
---@return string[]
function M.errors(session)
  local merged, result = {}, {}
  for key, item in pairs(session.media_failures or {}) do
    merged[key] = item
  end
  for key, item in pairs(session.media_skipped or {}) do
    merged[key] = item
  end
  for _, item in pairs(merged) do
    result[#result + 1] = item.label .. ": " .. item.message
  end
  table.sort(result)
  return result
end

---@param session MdReadableSession
function M.close(session)
  local state = states[session]
  if not state then
    return
  end
  states[session] = nil
  clear(state)
  require("md-readable.providers.mermaid").close(session)
  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
  end
end

return M
