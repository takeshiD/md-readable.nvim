-- Git status of the source in the reading buffer's sign column: the source
-- (with unsaved edits) is compared with the Git index, and every display row
-- that shows a changed source row gets a sign (git.enable).
local M = {}
local namespace = vim.api.nvim_create_namespace("MdReadableGit")
---@type table<MdReadableSession, MdReadableGitState>
local states = setmetatable({}, { __mode = "k" })

---@alias MdReadableGitKind "add"|"change"|"delete"
---@class MdReadableGitHunk
---@field start_row integer 0-based source row
---@field end_row integer 0-based, exclusive
---@field kind MdReadableGitKind
---@class MdReadableGitState
---@field buf integer Source buffer being compared
---@field hunks MdReadableGitHunk[]
---@field generation integer
---@field tick? integer Source changedtick the hunks were requested for
---@field timer uv.uv_timer_t Debounce timer
---@field group integer Autocommand group id
---@field process? vim.SystemObj Running git command
---@field watcher? uv.uv_fs_poll_t Git index watcher
---@field root? string Repository top level

---@type table<MdReadableGitKind, {text:string, group:string}>
M.signs = {
  add = { text = "▎", group = "MdReadableGitAdd" },
  change = { text = "▎", group = "MdReadableGitChange" },
  delete = { text = "▁", group = "MdReadableGitDelete" },
}

-- Hunks of the source against the indexed text. A deletion marks the row
-- after it (the last row when it removed the end of the file).
---@param index string Indexed text
---@param source string Buffer text
---@param row_count integer
---@return MdReadableGitHunk[]
function M.diff(index, source, row_count)
  local hunks = {}
  local ok, result = pcall(vim.text.diff, index, source, { result_type = "indices", algorithm = "histogram" })
  if not ok then
    return hunks
  end
  ---@cast result integer[][]
  for _, hunk in ipairs(result) do
    local old_count, start, count = hunk[2], hunk[3], hunk[4]
    local row = count == 0 and math.max(0, math.min(start, row_count - 1)) or math.max(0, start - 1)
    hunks[#hunks + 1] = {
      start_row = row,
      end_row = row + math.max(1, count),
      kind = old_count == 0 and "add" or count == 0 and "delete" or "change",
    }
  end
  return hunks
end

-- Signs per display row (0-based): a row shows a hunk when one of the source
-- rows it renders is in it. A hunk on rows the view does not show (blank
-- lines, frontmatter, the place of a deletion) marks the next shown row.
-- Changes outrank additions, additions deletions.
---@param rendered MdReadableRendered
---@param hunks MdReadableGitHunk[]
---@return table<integer, MdReadableGitKind>
function M.project(rendered, hunks)
  local rank = { change = 3, add = 2, delete = 1 }
  local result = {}
  ---@param row integer 0-based display row
  ---@param kind MdReadableGitKind
  local function mark(row, kind)
    if not result[row] or rank[kind] > rank[result[row]] then
      result[row] = kind
    end
  end
  local sources = {}
  for index = 1, #rendered.lines do
    sources[index] = rendered.source_rows and rendered.source_rows[index] or { rendered.row_map[index] }
  end
  for _, hunk in ipairs(hunks) do
    local shown, after = false, nil
    for index, rows in ipairs(sources) do
      for _, source_row in ipairs(rows) do
        if source_row >= hunk.start_row and source_row < hunk.end_row then
          mark(index - 1, hunk.kind)
          shown = true
        elseif source_row >= hunk.end_row and not after then
          after = index - 1
        end
      end
    end
    if not shown and #sources > 0 then
      mark(after or #sources - 1, hunk.kind)
    end
  end
  return result
end

-- Places the signs of the stored hunks; called after every render.
---@param session MdReadableSession
function M.draw(session)
  if not vim.api.nvim_buf_is_valid(session.read_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(session.read_buf, namespace, 0, -1)
  local state = states[session]
  if not state or not session.rendered then
    return
  end
  local last = vim.api.nvim_buf_line_count(session.read_buf) - 1
  for row, kind in pairs(M.project(session.rendered, state.hunks)) do
    if row <= last then
      local sign = M.signs[kind]
      vim.api.nvim_buf_set_extmark(session.read_buf, namespace, row, 0, {
        sign_text = sign.text,
        sign_hl_group = sign.group,
        priority = 10,
      })
    end
  end
end

---@param handle? uv.uv_timer_t|uv.uv_fs_poll_t
local function stop(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

---@param session MdReadableSession
---@param state MdReadableGitState
---@param generation integer
local function run(session, state, generation)
  local buf = state.buf
  if states[session] ~= state or session.closed or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local source = table.concat(lines, "\n") .. (vim.bo[buf].endofline and "\n" or "")
  ---@return boolean
  local function fresh()
    return states[session] == state
      and not session.closed
      and state.generation == generation
      and vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_get_changedtick(buf) == tick
  end
  ---@param hunks MdReadableGitHunk[]
  local function publish(hunks)
    if fresh() then
      state.hunks = hunks
      M.draw(session)
    end
  end
  if path == "" or vim.fn.executable("git") ~= 1 then
    publish({})
    return
  end
  ---@param args string[]
  ---@param callback fun(result:vim.SystemCompleted)
  local function command(args, callback)
    if not fresh() then
      return
    end
    local ok, process = pcall(vim.system, args, { text = true, timeout = 10000 }, function(result)
      vim.schedule(function()
        if fresh() then
          state.process = nil
          callback(result)
        end
      end)
    end)
    if ok then
      state.process = process
    else
      publish({})
    end
  end
  command({ "git", "-C", vim.fs.dirname(path), "rev-parse", "--show-toplevel" }, function(root_result)
    if root_result.code ~= 0 then
      publish({})
      return
    end
    local root = root_result.stdout:gsub("[\r\n]+$", "")
    if path:sub(1, #root + 1) ~= root .. "/" then
      publish({})
      return
    end
    local relative = path:sub(#root + 2)
    local function compare()
      command({ "git", "-C", root, "show", ":" .. relative }, function(result)
        if result.code == 0 then
          publish(M.diff(result.stdout, source, #lines))
        else
          -- Not in the index: an untracked file is all additions.
          command({ "git", "-C", root, "ls-files", "--error-unmatch", "--", relative }, function(tracked)
            publish(tracked.code == 1 and M.diff("", source, #lines) or {})
          end)
        end
      end)
    end
    if state.root == root and state.watcher then
      compare()
      return
    end
    -- Staging or committing changes the index, not the buffer: poll it.
    command({ "git", "-C", root, "rev-parse", "--path-format=absolute", "--git-path", "index" }, function(index_result)
      stop(state.watcher)
      state.watcher = nil
      if index_result.code == 0 then
        local index_path = index_result.stdout:gsub("[\r\n]+$", "")
        local watcher = assert(vim.uv.new_fs_poll())
        local ok = watcher:start(index_path, 1000, function()
          vim.schedule(function()
            if states[session] == state then
              M.update(session)
            end
          end)
        end)
        if ok then
          state.watcher, state.root = watcher, root
        else
          stop(watcher)
        end
      end
      compare()
    end)
  end)
end

-- Recomputes the hunks (debounced, asynchronous).
---@param session MdReadableSession
function M.update(session)
  local state = states[session]
  if not state or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  state.tick = vim.api.nvim_buf_get_changedtick(state.buf)
  state.generation = state.generation + 1
  local generation = state.generation
  if state.process then
    pcall(state.process.kill, state.process, 15)
    state.process = nil
  end
  state.timer:stop()
  state.timer:start(80, 0, function()
    vim.schedule(function()
      run(session, state, generation)
    end)
  end)
end

-- Starts comparing the session's source; a no-op while it is unchanged.
---@param session MdReadableSession
function M.attach(session)
  local state = states[session]
  if (session.config.git or {}).enable == false or (state and state.buf == session.source_buf) then
    return
  end
  M.close(session)
  state = {
    buf = session.source_buf,
    hunks = {},
    generation = 0,
    timer = assert(vim.uv.new_timer()),
    group = vim.api.nvim_create_augroup("MdReadableGit" .. session.id, { clear = true }),
  }
  states[session] = state
  -- Source edits re-render the view, which calls M.refresh. Staging from
  -- another program is caught by the index watcher or on focus.
  vim.api.nvim_create_autocmd("FocusGained", {
    group = state.group,
    callback = function()
      M.update(session)
    end,
  })
  M.update(session)
end

-- After a render: redraws the signs, and compares again when the source
-- changed (edits, reloads) since the last comparison.
---@param session MdReadableSession
function M.refresh(session)
  local state = states[session]
  if not state then
    return
  end
  M.draw(session)
  if vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_buf_get_changedtick(state.buf) ~= state.tick then
    M.update(session)
  end
end

---@param session MdReadableSession
---@return MdReadableGitHunk[]? hunks Current hunks of an attached session
function M.hunks(session)
  return states[session] and states[session].hunks
end

---@param session MdReadableSession
function M.close(session)
  local state = states[session]
  if not state then
    return
  end
  states[session] = nil
  stop(state.timer)
  stop(state.watcher)
  if state.process then
    pcall(state.process.kill, state.process, 15)
  end
  pcall(vim.api.nvim_del_augroup_by_id, state.group)
  if vim.api.nvim_buf_is_valid(session.read_buf) then
    vim.api.nvim_buf_clear_namespace(session.read_buf, namespace, 0, -1)
  end
end

return M
