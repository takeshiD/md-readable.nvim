---@class MdReadableSessionModule
---@field sessions table<integer, MdReadableSession> Open sessions by id
---@field next_id integer
---@field watchers table<integer, true> Source buffers with an nvim_buf_attach watcher
local M = { sessions = {}, next_id = 0, watchers = {} }
---@class MdReadableSession
local Session = {}
Session.__index = Session
local ns = vim.api.nvim_create_namespace("md-readable.render")
---@param win? integer
---@return boolean?
local function valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end
---@param win integer
---@param buf integer
local function switch_buffer(win, buf)
  vim.api.nvim_win_call(win, function()
    vim.cmd("keepjumps keepalt hide buffer " .. tostring(buf))
  end)
end
-- Calls an optional module function; missing modules or functions are ignored.
---@param name string Module name below "md-readable."
---@param action string
---@param ... any
---@return any
local function service(name, action, ...)
  local ok, module = pcall(require, "md-readable." .. name)
  if ok and module[action] then
    return module[action](...)
  end
end
-- Sets the cursor clamped to the buffer; row and col are 0-based.
---@param win integer
---@param row integer
---@param col? integer
local function cursor(win, row, col)
  if not valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  row = math.max(0, math.min(row, vim.api.nvim_buf_line_count(buf) - 1))
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  vim.api.nvim_win_set_cursor(win, { row + 1, math.max(0, math.min(col or 0, #line)) })
end
---@return table<integer, MdReadableSession>
function M.all()
  return M.sessions
end
-- Session whose reader, source, navigation panel or minimap window is current.
---@return MdReadableSession?
function M.current()
  local win = vim.api.nvim_get_current_win()
  for _, s in pairs(M.sessions) do
    if not s.closed and s.read_win == win then
      return s
    end
  end
  for _, s in pairs(M.sessions) do
    if not s.closed and s.source_win == win then
      return s
    end
  end
  for _, s in pairs(M.sessions) do
    if not s.closed then
      for _, panel in pairs((s._navigation or {}).panels or {}) do
        if panel.win == win then
          return s
        end
      end
      local minimap = require("md-readable.minimap").get(s)
      if minimap and minimap.win == win then
        return s
      end
    end
  end
end
---@param row integer 0-based source row
---@param col? integer 0-based source byte column
function Session:jump_source(row, col)
  local display_row, display_col = self.map:to_display(row, col or 0)
  self.busy = true
  cursor(self.read_win, display_row, display_col)
  if
    self.mode ~= "current"
    and valid(self.source_win)
    and vim.api.nvim_win_get_buf(self.source_win) == self.source_buf
  then
    cursor(self.source_win, row, col)
  end
  self.busy = false
  if valid(self.read_win) then
    vim.api.nvim_set_current_win(self.read_win)
  end
  service("reader.focus", "update", self)
  service("minimap", "update", self)
end
---@param from integer Window the cursor moved in
function Session:sync(from)
  if self.busy or self.closed or not self.map then
    return
  end
  self.busy = true
  if from == self.read_win then
    local pos = vim.api.nvim_win_get_cursor(from)
    local row, col = self.map:to_source(pos[1] - 1, pos[2])
    if
      self.mode ~= "current"
      and valid(self.source_win)
      and vim.api.nvim_win_get_buf(self.source_win) == self.source_buf
    then
      cursor(self.source_win, row, col)
    end
  elseif from == self.source_win and self.mode ~= "current" then
    local pos = vim.api.nvim_win_get_cursor(from)
    local row, col = self.map:to_display(pos[1] - 1, pos[2])
    cursor(self.read_win, row, col)
  end
  self.busy = false
end
function Session:load_navigation()
  local path = vim.api.nvim_buf_get_name(self.source_buf)
  if path == "" then
    return
  end
  local ok, result = pcall(function()
    return require("md-readable.navigation.detect").load(path, self.config.adapters)
  end)
  if ok and result then
    self.nav_result = result
    if result.snapshot then
      self.snapshot = result.snapshot
      self.stale = false
    elseif result.status == "none" then
      self.snapshot, self.stale = nil, false
    elseif self.snapshot and path:sub(1, #self.snapshot.rootDir + 1) == self.snapshot.rootDir .. "/" then
      self.stale = true
    else
      self.snapshot, self.stale = nil, false
    end
  else
    ---@diagnostic disable-next-line: missing-fields -- diagnostic without severity/code
    self.nav_result = { status = "error", diagnostics = { { message = tostring(result) } } }
  end
end
function Session:refresh()
  if self.closed or not valid(self.read_win) or not vim.api.nvim_buf_is_valid(self.source_buf) then
    return
  end
  local saved = vim.api.nvim_win_get_cursor(self.read_win)
  local row, col = saved[1] - 1, saved[2]
  if self.map then
    row, col = self.map:to_source(row, col)
  end
  self.generation = self.generation + 1
  local document =
    require("md-readable.document.parser").parse(vim.api.nvim_buf_get_lines(self.source_buf, 0, -1, false), {
      bufnr = self.source_buf,
      changedtick = vim.api.nvim_buf_get_changedtick(self.source_buf),
      path = vim.api.nvim_buf_get_name(self.source_buf),
    })
  document.changedtick = vim.api.nvim_buf_get_changedtick(self.source_buf)
  local opts = vim.deepcopy(self.config) --[[@as MdReadableRenderOptions]]
  opts.tabstop = vim.bo[self.source_buf].tabstop
  vim.bo[self.read_buf].tabstop = opts.tabstop
  local total = vim.api.nvim_win_get_width(self.read_win)
  opts.width = math.max(12, math.min(opts.width, total - 2))
  -- Center the body in wide windows with a blank status column, which keeps
  -- buffer text, SourceMap columns and search independent of the margin.
  local margin = self.config.center ~= false and math.max(0, math.floor((total - opts.width) / 2)) or 0
  local statuscolumn = margin > 0 and string.rep(" ", margin) or ""
  if vim.wo[self.read_win].statuscolumn ~= statuscolumn then
    vim.wo[self.read_win].statuscolumn = statuscolumn
  end
  opts.expanded, opts.tabs = self.expanded, self.tabs
  local image_ok, image = pcall(require, "md-readable.providers.image")
  local capable = image_ok and image.capabilities and image.capabilities()
  opts.media = {
    enabled = self.config.images.enabled and not not capable,
    image_height = self.config.images.height,
    reserve = image_ok and image.reserver and image.reserver(self) or nil,
  }
  local rendered = require("md-readable.reader.render").render(document, opts)
  if #rendered.lines == 0 then
    rendered.lines = { "" }
  end
  local map = require("md-readable.reader.source_map").new(document.lines, rendered)
  vim.bo[self.read_buf].modifiable = true
  local written, err = pcall(vim.api.nvim_buf_set_lines, self.read_buf, 0, -1, false, rendered.lines)
  vim.bo[self.read_buf].modifiable = false
  if not written then
    error(err)
  end
  vim.bo[self.read_buf].modified = false
  self.document, self.rendered, self.map = document, rendered, map
  vim.api.nvim_buf_clear_namespace(self.read_buf, ns, 0, -1)
  for _, h in ipairs(self.rendered.highlights or {}) do
    local line = self.rendered.lines[h.row + 1] or ""
    if h.start_col < #line and h.end_col > h.start_col then
      pcall(vim.api.nvim_buf_set_extmark, self.read_buf, ns, h.row, h.start_col, {
        end_col = math.min(h.end_col, #line),
        hl_group = h.group,
        priority = 100,
      })
    end
  end
  service("ui.theme", "apply", self.read_win, self.config.theme, self.config)
  local dr, dc = self.map:to_display(row, col)
  cursor(self.read_win, dr, dc)
  service("reader.focus", "update", self)
  service("minimap", "update", self)
  service("ui.navigation", "update", self)
  service("providers.image", "update", self)
  service("minimap.git", "update", self)
end
function Session:schedule()
  self.pending = (self.pending or 0) + 1
  local pending = self.pending
  vim.defer_fn(function()
    if not self.closed and pending == self.pending then
      local ok, err = pcall(self.refresh, self)
      if not ok then
        vim.notify("md-readable: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end, self.config.debounce)
end
---@param key string Raw jump key (CTRL-O or CTRL-I)
---@param count? integer
function Session:native_jump(key, count)
  local position = vim.api.nvim_win_get_cursor(self.read_win)
  local row, col = self.map:to_source(position[1] - 1, position[2])
  self.busy = true
  switch_buffer(self.read_win, self.source_buf)
  cursor(self.read_win, row, col)
  vim.api.nvim_win_call(self.read_win, function()
    vim.cmd("normal! " .. tostring(count or 1) .. key)
  end)
  local target = vim.api.nvim_win_get_buf(self.read_win)
  local destination = vim.api.nvim_win_get_cursor(self.read_win)
  self.source_buf = target
  switch_buffer(self.read_win, self.read_buf)
  if self.mode ~= "current" and valid(self.source_win) then
    vim.api.nvim_win_set_buf(self.source_win, target)
  end
  self.busy = false
  self:attach_source()
  self:load_navigation()
  self:refresh()
  self:jump_source(destination[1] - 1, destination[2])
end
function Session:attach_source()
  if M.watchers[self.source_buf] then
    return
  end
  local buf = self.source_buf
  M.watchers[buf] = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      local active = false
      for _, s in pairs(M.sessions) do
        if not s.closed and s.source_buf == buf then
          s:schedule()
          active = true
        end
      end
      if not active then
        M.watchers[buf] = nil
        return true
      end
    end,
    on_detach = function()
      M.watchers[buf] = nil
      vim.schedule(function()
        for _, s in pairs(M.sessions) do
          if not s.closed and s.source_buf == buf then
            M.close(s)
          end
        end
      end)
    end,
  })
end
---@param path string
---@param anchor? string
---@return boolean? ok false when the anchor is unresolved
function Session:navigate(path, anchor)
  if self.closed then
    return
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if vim.fn.filereadable(path) == 0 and vim.fn.bufnr(path) < 0 then
    vim.notify("md-readable: document unavailable: " .. path, vim.log.levels.WARN)
    return
  end
  local anchor_row
  if anchor and anchor ~= "" then
    local resolved = require("md-readable.navigation.resolver").resolve(
      { type = "document", path = path, anchor = anchor },
      {
        path = path,
        root_dir = self.snapshot and self.snapshot.rootDir or vim.fs.dirname(path),
        snapshot = self.snapshot,
        headings = path == vim.api.nvim_buf_get_name(self.source_buf) and self.document.headings or nil,
      }
    )
    if not resolved or resolved.type ~= "document" or resolved.row == nil then
      vim.notify("md-readable: unresolved anchor: " .. anchor, vim.log.levels.WARN)
      return false
    end
    anchor_row = resolved.row
  end
  local position = vim.api.nvim_win_get_cursor(self.read_win)
  local source_row, source_col = self.map:to_source(position[1] - 1, position[2])
  self.positions[vim.api.nvim_buf_get_name(self.source_buf)] = { source_row, source_col }
  -- Put the original document in the native jumplist. The reader buffer is
  -- retained while visiting source entries, so Ctrl-O/Ctrl-I remain useful.
  self.busy = true
  switch_buffer(self.read_win, self.source_buf)
  cursor(self.read_win, source_row, source_col)
  vim.api.nvim_win_call(self.read_win, function()
    vim.cmd("normal! m'")
  end)
  switch_buffer(self.read_win, self.read_buf)
  self.busy = false
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  self.busy = true
  self.source_buf = buf
  if self.mode ~= "current" and valid(self.source_win) then
    vim.api.nvim_win_set_buf(self.source_win, buf)
  end
  self.busy = false
  self:attach_source()
  if
    not self.snapshot
    or (self.snapshot.rootDir ~= "/" and path:sub(1, #self.snapshot.rootDir + 1) ~= self.snapshot.rootDir .. "/")
  then
    self:load_navigation()
  end
  self:refresh()
  local dest = self.positions[path] or { 0, 0 }
  if anchor_row ~= nil then
    dest = { anchor_row, 0 }
  end
  self:jump_source(dest[1], dest[2])
  return true
end
---@param mode? MdReadableSessionMode
---@return MdReadableSession
function M.open(mode)
  mode = mode or "current"
  if vim.o.columns < 16 or vim.o.lines < 6 then
    require("md-readable.errors").user("Reading view needs at least 16 columns and 6 rows")
  end
  local origin_win, origin_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local current = M.current()
  if current then
    if current.mode == mode then
      vim.api.nvim_set_current_win(current.read_win)
      return current
    end
    origin_win, origin_buf = current.source_win, current.source_buf
    if current.mode == "current" then
      M.close(current)
    end
  end
  for _, s in pairs(M.sessions) do
    if not s.closed and s.source_win == origin_win and s.source_buf == origin_buf and s.mode == mode then
      vim.api.nvim_set_current_win(s.read_win)
      return s
    end
  end
  local config = require("md-readable.config").get()
  M.next_id = M.next_id + 1
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "md-readable"
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "md-readable://" .. M.next_id)
  local original_cursor = vim.api.nvim_win_get_cursor(origin_win)
  local win
  if mode == "vert" then
    win = vim.api.nvim_open_win(buf, true, { split = "right", win = origin_win })
  elseif mode == "float" then
    -- The float never exceeds the body width plus a small margin.
    local width = math.max(12, math.min(math.floor(vim.o.columns * config.float.width), config.width + 4))
    local height = math.max(3, math.floor((vim.o.lines - 2) * config.float.height))
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      width = math.min(width, vim.o.columns - 2),
      height = height,
      style = "minimal",
      border = config.float.border,
      title = " Markdown ",
      title_pos = "center",
    })
  else
    win = origin_win
    vim.api.nvim_win_set_buf(win, buf)
  end
  local saved_options = {}
  for _, option in ipairs({
    "wrap",
    "number",
    "relativenumber",
    "signcolumn",
    "foldcolumn",
    "conceallevel",
    "cursorline",
    "statuscolumn",
  }) do
    saved_options[option] = vim.wo[win][option]
  end
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].conceallevel = 0
  ---@type MdReadableSession
  local self = setmetatable({
    id = M.next_id,
    source_buf = origin_buf,
    source_win = origin_win,
    read_buf = buf,
    read_win = win,
    mode = mode,
    config = config,
    generation = 0,
    closed = false,
    expanded = {},
    tabs = {},
    positions = {},
    attached = {},
    saved_options = saved_options,
  }, Session)
  M.sessions[self.id] = self
  self.group = vim.api.nvim_create_augroup("MdReadableSession" .. self.id, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = self.group,
    callback = function()
      if self.closed or self.busy then
        return
      end
      local current_win = vim.api.nvim_get_current_win()
      if current_win == self.read_win or current_win == self.source_win then
        self:sync(current_win)
        service("reader.focus", "update", self)
        service("minimap", "update", self)
        service("ui.navigation", "update", self)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = self.group,
    buffer = buf,
    callback = function()
      require("md-readable.reader.yank").handle(self, vim.v.event)
    end,
  })
  vim.api.nvim_create_autocmd({ "WinResized", "ColorScheme" }, {
    group = self.group,
    callback = function()
      self:schedule()
    end,
  })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = self.group,
    callback = function()
      service("providers.image", "update", self)
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = self.group,
    callback = function(args)
      if self.closed or self.busy or args.buf == self.read_buf then
        return
      end
      local here = vim.api.nvim_get_current_win()
      if here == self.read_win then
        local target, point = args.buf, vim.api.nvim_win_get_cursor(here)
        local name = vim.api.nvim_buf_get_name(target)
        if vim.bo[target].filetype == "markdown" or name:match("%.md[x]?$") then
          vim.schedule(function()
            if self.closed or not valid(self.read_win) or not vim.api.nvim_buf_is_valid(target) then
              return
            end
            self.busy = true
            self.source_buf = target
            switch_buffer(self.read_win, self.read_buf)
            if self.mode ~= "current" and valid(self.source_win) then
              vim.api.nvim_win_set_buf(self.source_win, target)
            end
            self.busy = false
            self:attach_source()
            self:load_navigation()
            self:refresh()
            self:jump_source(point[1] - 1, point[2])
          end)
        else
          vim.schedule(function()
            M.close(self)
          end)
        end
        return
      end
      if here ~= self.source_win or self.mode == "current" or args.buf == self.source_buf then
        return
      end
      if vim.bo[args.buf].buftype == "" then
        self.source_buf = args.buf
        self:attach_source()
        self:load_navigation()
        self:schedule()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = self.group,
    callback = function()
      if not self.closed then
        self:load_navigation()
        self:schedule()
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.group,
    pattern = tostring(win),
    callback = function()
      vim.schedule(function()
        M.close(self)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = self.group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        M.close(self)
      end)
    end,
  })
  require("md-readable.reader.yank").attach(self)
  for lhs, key in pairs({ ["<C-o>"] = string.char(15), ["<C-i>"] = string.char(9) }) do
    vim.keymap.set("n", lhs, function()
      self:native_jump(key, vim.v.count1)
    end, { buffer = buf, desc = "Follow native source jumplist" })
  end
  require("md-readable.keymaps").attach(buf, config.keymaps)
  self:attach_source()
  local ok, err = pcall(function()
    self:load_navigation()
    self:refresh()
    self:jump_source(original_cursor[1] - 1, original_cursor[2])
  end)
  if not ok then
    M.close(self)
    error(err)
  end
  if config.navigation.auto_open and self.snapshot and mode ~= "float" then
    service("ui.navigation", "open", self)
  end
  return self
end
---@param self? MdReadableSession Defaults to the current session
function M.source(self)
  self = self or M.current()
  if not self then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(self.read_win)
  local row, col = self.map:to_source(pos[1] - 1, pos[2])
  if self.mode == "current" then
    M.close(self)
  elseif valid(self.source_win) then
    vim.api.nvim_set_current_win(self.source_win)
  end
  cursor(self.source_win, row, col)
end
---@param self? MdReadableSession Defaults to the current session
function M.close(self)
  self = self or M.current()
  if not self or self.closed then
    return
  end
  self.closed = true
  self.generation = self.generation + 1
  service("ui.navigation", "close", self)
  service("minimap", "close", self)
  if self._links_panel then
    pcall(vim.api.nvim_win_close, self._links_panel.win, true)
    self._links_panel = nil
  end
  service("providers.image", "close", self)
  service("reader.focus", "close", self)
  service("ui.theme", "close", self.read_win)
  pcall(vim.api.nvim_del_augroup_by_id, self.group)
  if valid(self.read_win) and vim.api.nvim_win_get_buf(self.read_win) == self.read_buf then
    if self.mode == "current" then
      if vim.api.nvim_buf_is_valid(self.source_buf) then
        vim.api.nvim_win_set_buf(self.read_win, self.source_buf)
      end
      for key, value in pairs(self.saved_options) do
        vim.wo[self.read_win][key] = value
      end
    else
      pcall(vim.api.nvim_win_close, self.read_win, true)
    end
  end
  if vim.api.nvim_buf_is_valid(self.read_buf) then
    pcall(vim.api.nvim_buf_delete, self.read_buf, { force = true })
  end
  M.sessions[self.id] = nil
end
return M
