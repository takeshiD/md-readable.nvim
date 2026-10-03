local M = { sessions = {}, next_id = 0 }
local Session = {}
Session.__index = Session
local ns = vim.api.nvim_create_namespace("md-readable.render")
local function valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end
local function switch_buffer(win, buf)
  vim.api.nvim_win_call(win, function()
    vim.cmd("keepjumps keepalt hide buffer " .. tostring(buf))
  end)
end
local function service(name, action, ...)
  local ok, module = pcall(require, "md-readable." .. name)
  if ok and module[action] then
    return module[action](...)
  end
end
local function cursor(win, row, col)
  if not valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  row = math.max(0, math.min(row, vim.api.nvim_buf_line_count(buf) - 1))
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  vim.api.nvim_win_set_cursor(win, { row + 1, math.max(0, math.min(col or 0, #line)) })
end
function M.all()
  return M.sessions
end
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
end
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
  service("nav.minimap", "update", self)
end
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
  self.document =
    require("md-readable.document.parser").parse(vim.api.nvim_buf_get_lines(self.source_buf, 0, -1, false), {
      bufnr = self.source_buf,
      changedtick = vim.api.nvim_buf_get_changedtick(self.source_buf),
      path = vim.api.nvim_buf_get_name(self.source_buf),
    })
  self.document.changedtick = vim.api.nvim_buf_get_changedtick(self.source_buf)
  local opts = vim.deepcopy(self.config)
  opts.width = math.max(12, math.min(opts.width, vim.api.nvim_win_get_width(self.read_win) - 2))
  opts.expanded, opts.tabs = self.expanded, self.tabs
  local image_ok, image = pcall(require, "md-readable.providers.image")
  local capable = image_ok and image.capabilities and image.capabilities()
  opts.media = { enabled = self.config.images.enabled and not not capable, image_height = self.config.images.height }
  self.rendered = require("md-readable.reader.render").render(self.document, opts)
  if #self.rendered.lines == 0 then
    self.rendered.lines = { "" }
  end
  self.map = require("md-readable.reader.source_map").new(self.document.lines, self.rendered)
  vim.bo[self.read_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.read_buf, 0, -1, false, self.rendered.lines)
  vim.bo[self.read_buf].modifiable = false
  vim.bo[self.read_buf].modified = false
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
  service("nav.minimap", "update", self)
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
  if self.attached[self.source_buf] then
    return
  end
  self.attached[self.source_buf] = true
  local buf = self.source_buf
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      if self.closed then
        return true
      end
      if self.source_buf == buf then
        self:schedule()
      end
    end,
    on_detach = function()
      if not self.closed and self.source_buf == buf then
        vim.schedule(function()
          M.close(self)
        end)
      end
    end,
  })
end
function Session:navigate(path, anchor)
  if self.closed then
    return
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if vim.fn.filereadable(path) == 0 and vim.fn.bufnr(path) < 0 then
    vim.notify("md-readable: document unavailable: " .. path, vim.log.levels.WARN)
    return
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
  if not self.snapshot or path:sub(1, #self.snapshot.rootDir) ~= self.snapshot.rootDir then
    self:load_navigation()
  end
  self:refresh()
  local dest = self.positions[path] or { 0, 0 }
  if anchor and anchor ~= "" then
    local resolver = require("md-readable.navigation.resolver")
    local resolved = resolver.resolve({ type = "document", path = path, anchor = anchor }, {
      path = path,
      root_dir = self.snapshot and self.snapshot.rootDir or vim.fs.dirname(path),
      headings = self.document.headings,
    })
    if resolved and resolved.row then
      dest = { resolved.row, 0 }
    else
      vim.notify("md-readable: unresolved anchor: " .. anchor, vim.log.levels.WARN)
    end
  end
  self:jump_source(dest[1], dest[2])
end
function M.open(mode)
  mode = mode or "current"
  if vim.o.columns < 16 or vim.o.lines < 6 then
    error("Reading view needs at least 16 columns and 6 rows")
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
    local width = math.max(12, math.floor(vim.o.columns * config.float.width))
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
  }) do
    saved_options[option] = vim.wo[win][option]
  end
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].conceallevel = 0
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
        service("nav.minimap", "update", self)
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
  if config.keymaps then
    vim.keymap.set("n", "q", function()
      M.close(self)
    end, { buffer = buf, desc = "Close reading view" })
    vim.keymap.set("n", "<CR>", function()
      require("md-readable").action("open")
    end, { buffer = buf, desc = "Open reader item" })
  end
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
function M.close(self)
  self = self or M.current()
  if not self or self.closed then
    return
  end
  self.closed = true
  self.generation = self.generation + 1
  service("ui.navigation", "close", self)
  service("nav.minimap", "close", self)
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
