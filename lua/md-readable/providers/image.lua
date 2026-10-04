local M = {}
local cache = require("md-readable.image.cache")
local capabilities = require("md-readable.image.capabilities")
local convert = require("md-readable.image.convert")
local display = require("md-readable.image.display")
---@class MdReadableImageState
---@field cancel fun()[]
---@field epoch integer Bumped on each redraw; stale callbacks compare against it
---@field group? integer Autocommand group
---@field signature? string Inputs of the last redraw
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
---@return fun(descriptor:MdReadableRenderedImage):boolean
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
    return true
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
    or opts.enabled == false
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
      callback = function()
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
  local parts = {
    session.generation or 0,
    session.read_win,
    info.topline,
    info.botline,
    info.winrow,
    info.wincol,
    info.width,
    info.height,
    info.leftcol or 0,
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
  if state.signature == signature then
    return
  end
  state.signature, state.epoch = signature, state.epoch + 1
  clear(state)
  local epoch = state.epoch
  ---@return boolean
  local function fresh()
    return states[session] == state and state.epoch == epoch and not session.closed
  end
  for _, image in ipairs(session.rendered.images or {}) do
    local descriptor = vim.deepcopy(image)
    descriptor.height = descriptor.height or opts.height or 10
    descriptor.width = math.min(descriptor.width or info.width, opts.max_width or info.width)
    local visible = descriptor.height > 0
      and descriptor.row
      and descriptor.row < info.botline
      and descriptor.row + descriptor.height > info.topline - 1
    if visible then
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
        state.cancel[#state.cancel + 1] = require("md-readable.providers.mermaid").render(session, descriptor, show)
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
