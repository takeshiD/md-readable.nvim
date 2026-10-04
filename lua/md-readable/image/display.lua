-- Kitty placement/cropping approach informed by md-render.nvim.
-- Copyright (c) 2026 delphinus. MIT License.
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
local M = {}
local cache = require("md-readable.image.cache")
local next_id = 1000000
---@class MdReadableImageGeometry
---@field row integer Screen row (1-based)
---@field col integer Screen column (1-based)
---@field columns integer Cells wide
---@field rows integer Cells tall
---@field x integer Source crop x (pixels)
---@field y integer Source crop y (pixels)
---@field width integer Source crop width (pixels)
---@field height integer Source crop height (pixels)
---@type table<integer, true>
local active = {}

---@param data string
local function send(data)
  if vim.env.TMUX then
    data = "\27Ptmux;" .. data:gsub("\27", "\27\27") .. "\27\\"
  end
  vim.api.nvim_ui_send(data)
end

---@param data string PNG bytes
---@return integer? width
---@return integer|string height_or_err
function M.dimensions(data)
  if data:sub(1, 8) ~= "\137PNG\13\10\26\10" or #data < 24 then
    return nil, "invalid PNG data"
  end
  ---@param at integer
  ---@return integer
  local function integer(at)
    local a, b, c, d = data:byte(at, at + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  local width, height = integer(17), integer(21)
  if width < 1 or height < 1 then
    return nil, "invalid PNG dimensions"
  end
  return width, height
end

---@param win integer
---@param descriptor MdReadableRenderedImage
---@param pixel_width integer
---@param pixel_height integer
---@return MdReadableImageGeometry?
function M.geometry(win, descriptor, pixel_width, pixel_height)
  if not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local info = vim.fn.getwininfo(win)[1]
  if not info then
    return nil
  end
  local start = descriptor.row
  local total_rows = descriptor.height or 8
  local top, bottom = math.max(start, info.topline - 1), math.min(start + total_rows, info.botline)
  if top >= bottom then
    return nil
  end
  local screen = vim.fn.screenpos(win, top + 1, 1)
  if screen.row == 0 or screen.col == 0 then
    return nil
  end
  local available = math.max(1, vim.api.nvim_win_get_width(win) - info.textoff)
  local columns = math.min(descriptor.width or available, available)
  -- Terminal cells are approximately twice as tall as wide. Keep the image's
  -- aspect ratio within its reserved rectangle; no text is used as a canvas.
  columns = math.max(1, math.min(columns, math.floor(total_rows * 2 * pixel_width / pixel_height)))
  total_rows = math.max(1, math.min(total_rows, math.ceil(columns * pixel_height / (2 * pixel_width))))
  bottom = math.min(start + total_rows, info.botline)
  if top >= bottom then
    return nil
  end
  local hidden = top - start
  local y = math.floor(pixel_height * hidden / total_rows)
  local height = math.max(1, math.floor(pixel_height * (bottom - top) / total_rows))
  return {
    row = screen.row,
    col = screen.col,
    columns = columns,
    rows = bottom - top,
    x = 0,
    y = y,
    width = pixel_width,
    height = math.min(height, pixel_height - y),
  }
end

---@param id integer Kitty image and placement id
---@param data string PNG bytes
---@param geometry MdReadableImageGeometry
---@return string
function M.protocol(id, data, geometry)
  local encoded, packets = vim.base64.encode(data), {}
  for first = 1, #encoded, 4096 do
    local last = math.min(#encoded, first + 4095)
    local more = last < #encoded and 1 or 0
    local control = first == 1
        and string.format(
          "a=T,f=100,t=d,i=%d,p=%d,c=%d,r=%d,x=%d,y=%d,w=%d,h=%d,C=1,q=2,m=%d",
          id,
          id,
          geometry.columns,
          geometry.rows,
          geometry.x,
          geometry.y,
          geometry.width,
          geometry.height,
          more
        )
      or "m=" .. more
    packets[#packets + 1] = "\27_G" .. control .. ";" .. encoded:sub(first, last) .. "\27\\"
  end
  return "\27[s\27[" .. geometry.row .. ";" .. geometry.col .. "H" .. table.concat(packets) .. "\27[u"
end

---@param path string PNG file
---@param win integer
---@param descriptor MdReadableRenderedImage
---@param opts? MdReadableConfigImages
---@param callback? fun(id:integer?,err:string?)
---@return integer id
---@return fun() cancel
function M.show(path, win, descriptor, opts, callback)
  next_id = next_id + 1
  local id = next_id
  active[id] = true
  local cancel = cache.read(path, (opts or {}).max_bytes, function(data, err)
    if not active[id] then
      return
    end
    if not data then
      active[id] = nil
      if callback then
        callback(nil, err)
      end
      return
    end
    local width, height = M.dimensions(data)
    if not width then
      active[id] = nil
      if callback then
        callback(nil, height --[[@as string]])
      end
      return
    end
    local geometry = M.geometry(win, descriptor, width, height --[[@as integer]])
    if not geometry then
      active[id] = nil
      if callback then
        callback(nil, "image is outside the viewport")
      end
      return
    end
    send(M.protocol(id, data, geometry))
    if callback then
      callback(id)
    end
  end)
  return id, function()
    cancel()
    M.delete(id)
  end
end

---@param id? integer
function M.delete(id)
  if not id or not active[id] then
    return
  end
  active[id] = nil
  send(string.format("\27_Ga=d,d=I,i=%d,q=2\27\\", id))
end

return M
