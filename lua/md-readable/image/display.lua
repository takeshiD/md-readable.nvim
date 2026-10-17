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
--
-- Images are shown with Kitty Unicode placeholders: the image is transmitted
-- once as a virtual placement, and the reserved rows of the reading buffer
-- carry placeholder characters whose foreground color names the image. The
-- image is then ordinary text to Neovim and to tmux, so it scrolls with the
-- buffer and disappears with the tmux window. The row/column diacritics are
-- those of the Kitty graphics protocol specification.
local M = {}
local cache = require("md-readable.image.cache")
local namespace = vim.api.nvim_create_namespace("MdReadableImages")
local placeholder = vim.fn.nr2char(0x10EEEE)
-- stylua: ignore
local diacritics = vim.tbl_map(function(hex)
  return vim.fn.nr2char(tonumber(hex, 16))
end, vim.split("0305,030D,030E,0310,0312,033D,033E,033F,0346,034A,034B,034C,0350,0351,0352,0357,035B,0363,0364,0365,0366,0367,0368,0369,036A,036B,036C,036D,036E,036F,0483,0484,0485,0486,0487,0592,0593,0594,0595,0597,0598,0599,059C,059D,059E,059F,05A0,05A1,05A8,05A9,05AB,05AC,05AF,05C4,0610,0611,0612,0613,0614,0615,0616,0617,0657,0658,0659,065A,065B,065D,065E,06D6,06D7,06D8,06D9,06DA,06DB,06DC,06DF,06E0,06E1,06E2,06E4,06E7,06E8,06EB,06EC,0730,0732,0733,0735,0736,073A,073D,073F,0740,0741,0743,0745,0747,0749,074A,07EB,07EC,07ED,07EE,07EF,07F0,07F1,07F3,0816,0817,0818,0819,081B,081C,081D,081E,081F,0820,0821,0822,0823,0825,0826,0827,0829,082A,082B,082C,082D,0951,0953,0954,0F82,0F83,0F86,0F87,135D,135E,135F,17DD,193A,1A17,1A75,1A76,1A77,1A78,1A79,1A7A,1A7B,1A7C,1B6B,1B6D,1B6E,1B6F,1B70,1B71,1B72,1B73,1CD0,1CD1,1CD2,1CDA,1CDB,1CE0,1DC0,1DC1,1DC3,1DC4,1DC5,1DC6,1DC7,1DC8,1DC9,1DCB,1DCC,1DD1,1DD2,1DD3,1DD4,1DD5,1DD6,1DD7,1DD8,1DD9,1DDA,1DDB,1DDC,1DDD,1DDE,1DDF,1DE0,1DE1,1DE2,1DE3,1DE4,1DE5,1DE6,1DFE,20D0,20D1,20D4,20D5,20D6,20D7,20DB,20DC,20E1,20E7,20E9,20F0,2CEF,2CF0,2CF1,2DE0,2DE1,2DE2,2DE3,2DE4,2DE5,2DE6,2DE7,2DE8,2DE9,2DEA,2DEB,2DEC,2DED,2DEE,2DEF,2DF0,2DF1,2DF2,2DF3,2DF4,2DF5,2DF6,2DF7,2DF8,2DF9,2DFA,2DFB,2DFC,2DFD,2DFE,2DFF,A66F,A67C,A67D,A6F0,A6F1,A8E0,A8E1,A8E2,A8E3,A8E4,A8E5,A8E6,A8E7,A8E8,A8E9,A8EA,A8EB,A8EC,A8ED,A8EE,A8EF,A8F0,A8F1,AAB0,AAB2,AAB3,AAB7,AAB8,AABE,AABF,AAC1,FE20,FE21,FE22,FE23,FE24,FE25,FE26,10A0F,10A38,1D185,1D186,1D187,1D188,1D189,1D1AA,1D1AB,1D1AC,1D1AD,1D242,1D243,1D244", ","))
---@class MdReadableImagePlacement
---@field buf integer Buffer holding the placeholder rows
---@field marks integer[] Extmark ids of the placeholder rows
---@type table<integer, MdReadableImagePlacement> Image id to its placement
local active = {}
local last_id = 0

---@param data string
local function send(data)
  if vim.env.TMUX then
    data = "\27Ptmux;" .. data:gsub("\27", "\27\27") .. "\27\\"
  end
  vim.api.nvim_ui_send(data)
end

-- The image id is the placeholder's foreground color: 24-bit with
-- 'termguicolors', otherwise a 256-color index.
---@return integer
local function allocate()
  local limit = vim.o.termguicolors and 0xFFFFFF or 255
  repeat
    last_id = last_id % limit + 1
  until not active[last_id] and (vim.o.termguicolors and last_id > 255 or not vim.o.termguicolors)
  return last_id
end

---@param data string PNG bytes
---@return integer? width Pixels
---@return integer|string height Pixels, or an error message
function M.dimensions(data)
  if data:sub(1, 8) ~= "\137PNG\13\10\26\10" or #data < 24 then
    return nil, "invalid PNG data"
  end
  ---@param at integer 1-based byte offset
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

---@type {width:number, height:number}?
local cell

-- Pixel size of one terminal cell from TIOCGWINSZ (as snacks.image does),
-- else a common 9x18. The UI may run in another process, so the controlling
-- terminal is tried after stdout and stderr.
---@return {width:number, height:number}
function M.cell_size()
  if cell then
    return cell
  end
  cell = { width = 9, height = 18 }
  local request = vim.fn.has("linux") == 1 and 0x5413
    or (vim.fn.has("mac") == 1 or vim.fn.has("bsd") == 1) and 0x40087468
    or nil
  local ok, ffi = pcall(require, "ffi")
  if not ok or not request then
    return cell
  end
  -- Declared one by one: another plugin may have declared some already.
  for _, declaration in ipairs({
    "typedef struct { unsigned short row, col, xpixel, ypixel; } md_readable_winsize;",
    "int ioctl(int, unsigned long, ...);",
    "int open(const char *, int, ...);",
    "int close(int);",
  }) do
    pcall(ffi.cdef, declaration)
  end
  pcall(function()
    local size = ffi.new("md_readable_winsize")
    local function query(fd)
      return fd >= 0 and ffi.C.ioctl(fd, request, size) == 0 and size.col > 0 and size.xpixel > 0
    end
    local found = query(1) or query(2)
    if not found then
      local tty = ffi.C.open("/dev/tty", 0)
      found = query(tty)
      if tty >= 0 then
        ffi.C.close(tty)
      end
    end
    if found then
      cell = { width = size.xpixel / size.col, height = size.ypixel / size.row }
    end
  end)
  return cell
end

-- Forgets the measured cell size (the font or the terminal may change).
function M.reset_cell_size()
  cell = nil
end

-- Cells an image takes inside a box of columns x rows, as snacks.image fits
-- it: its own size in cells when that fits, else the largest size with its
-- aspect ratio. `enlarge` fills the box even past the image's own size.
---@param pixel_width integer
---@param pixel_height integer
---@param columns integer Box width
---@param rows integer Box height
---@param enlarge? boolean
---@return integer columns
---@return integer rows
function M.fit(pixel_width, pixel_height, columns, rows, enlarge)
  local size = M.cell_size()
  local ratio = size.height / size.width -- cell height in cell widths
  columns, rows = math.max(1, columns), math.max(1, rows)
  if not enlarge then
    local natural_columns = math.max(1, math.ceil(pixel_width / size.width))
    local natural_rows = math.max(1, math.ceil(pixel_height / size.height))
    if natural_columns <= columns and natural_rows <= rows then
      return natural_columns, natural_rows
    end
  end
  local fit_columns = math.max(1, math.min(columns, math.floor(rows * ratio * pixel_width / pixel_height + 0.5)))
  local fit_rows = math.max(1, math.min(rows, math.ceil(fit_columns * pixel_height / (ratio * pixel_width) - 0.01)))
  return fit_columns, fit_rows
end

-- Cells the image covers: within the reserved rows and the text width,
-- keeping its aspect ratio. Images keep at most their own size; generated
-- diagrams fill their panel.
---@param win integer
---@param descriptor MdReadableRenderedImage
---@param pixel_width integer
---@param pixel_height integer
---@return integer columns
---@return integer rows
function M.size(win, descriptor, pixel_width, pixel_height)
  local info = vim.fn.getwininfo(win)[1]
  local available = math.max(1, (info and info.width - info.textoff) or vim.api.nvim_win_get_width(win))
  available = math.max(1, available - (descriptor.col or 0))
  local rows = math.min(#diacritics, math.max(1, descriptor.height or 8))
  local columns = math.min(#diacritics, descriptor.width or available, available)
  return M.fit(pixel_width, pixel_height, columns, rows, descriptor.kind == "mermaid")
end

-- Transmits the PNG and creates its virtual (placeholder) placement.
---@param id integer
---@param data string PNG bytes
---@param columns integer
---@param rows integer
---@return string
function M.protocol(id, data, columns, rows)
  local encoded, packets = vim.base64.encode(data), {}
  for first = 1, #encoded, 4096 do
    local last = math.min(#encoded, first + 4095)
    local more = last < #encoded and 1 or 0
    local control = first == 1 and string.format("a=t,f=100,t=d,i=%d,q=2,m=%d", id, more) or "m=" .. more
    packets[#packets + 1] = "\27_G" .. control .. ";" .. encoded:sub(first, last) .. "\27\\"
  end
  packets[#packets + 1] = string.format("\27_Ga=p,U=1,i=%d,c=%d,r=%d,C=1,q=2\27\\", id, columns, rows)
  return table.concat(packets)
end

-- Placeholder text of one image row.
---@param row integer 0-based
---@param columns integer
---@return string
function M.placeholders(row, columns)
  local cells = {}
  for column = 1, columns do
    cells[column] = placeholder .. diacritics[row + 1] .. diacritics[column]
  end
  return table.concat(cells)
end

---@param path string PNG file
---@param win integer
---@param descriptor MdReadableRenderedImage
---@param opts? MdReadableConfigImages
---@param callback? fun(id:integer?,err:string?)
---@return integer id
---@return fun() cancel
function M.show(path, win, descriptor, opts, callback)
  -- Transmitted images outlive Neovim unless deleted: clear them on exit.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("MdReadableImageDisplay", { clear = true }),
    callback = M.delete_all,
  })
  local id = allocate()
  local buf = vim.api.nvim_win_get_buf(win)
  active[id] = { buf = buf, marks = {} }
  ---@param err string
  local function failed(err)
    active[id] = nil
    if callback then
      callback(nil, err)
    end
  end
  local cancel = cache.read(path, (opts or {}).max_bytes, function(data, err)
    if not active[id] then
      return
    end
    if not data then
      return failed(err or "cannot read image")
    end
    local width, height = M.dimensions(data)
    if not width then
      return failed(height --[[@as string]])
    end
    if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
      return failed("reading window is closed")
    end
    local columns, rows = M.size(win, descriptor, width, height --[[@as integer]])
    send(M.protocol(id, data, columns, rows))
    local group = "MdReadableImage" .. id
    vim.api.nvim_set_hl(0, group, { fg = id, ctermfg = id <= 255 and id or nil })
    local last = vim.api.nvim_buf_line_count(buf) - 1
    for row = 0, rows - 1 do
      local line = (descriptor.row or 0) + row
      if line > last then
        break
      end
      active[id].marks[#active[id].marks + 1] = vim.api.nvim_buf_set_extmark(buf, namespace, line, 0, {
        virt_text = { { M.placeholders(row, columns), group } },
        virt_text_pos = "overlay",
        virt_text_win_col = descriptor.col or 0,
        -- Keep the background below (a code panel) behind transparent pixels.
        hl_mode = "combine",
      })
    end
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
  local placement = active[id]
  active[id] = nil
  if vim.api.nvim_buf_is_valid(placement.buf) then
    for _, mark in ipairs(placement.marks) do
      pcall(vim.api.nvim_buf_del_extmark, placement.buf, namespace, mark)
    end
  end
  send(string.format("\27_Ga=d,d=I,i=%d,q=2\27\\", id))
end

-- Deletes every image this plugin placed.
function M.delete_all()
  for id in pairs(vim.deepcopy(active)) do
    M.delete(id)
  end
end

return M
