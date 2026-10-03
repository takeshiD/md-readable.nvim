local M = {}
local cache = require("md-readable.image.cache")
local capabilities = require("md-readable.image.capabilities")
local convert = require("md-readable.image.convert")
local display = require("md-readable.image.display")
local states = setmetatable({}, { __mode = "k" })

function M.capabilities()
  return capabilities.get()
end

local function clear(state)
  for _, cancel in ipairs(state.cancel or {}) do
    pcall(cancel)
  end
  state.cancel = {}
end

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
  local function fresh()
    return states[session] == state and state.epoch == epoch and not session.closed
  end
  state.errors = {}
  for index, image in ipairs(session.rendered.images or {}) do
    local descriptor = vim.deepcopy(image)
    descriptor.height = descriptor.height or opts.height or 10
    descriptor.width = math.min(descriptor.width or info.width, opts.max_width or info.width)
    local visible = descriptor.row
      and descriptor.row < info.botline
      and descriptor.row + descriptor.height > info.topline - 1
    if visible then
      local function show(path, err)
        if not fresh() then
          return
        end
        if not path then
          state.errors[index] = err
          return
        end
        local cancel_conversion = convert.ensure(path, opts, function(png, conversion_err)
          if not fresh() then
            return
          end
          if not png then
            state.errors[index] = conversion_err
            return
          end
          local _, cancel_display = display.show(png, session.read_win, descriptor, opts, function(_, display_err)
            if fresh() and display_err then
              state.errors[index] = display_err
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

function M.errors(session)
  return vim.deepcopy((states[session] or {}).errors or {})
end

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
