local M = {}
---@type table<MdReadableSession, MdReadableMinimapGitState>
local states = setmetatable({}, { __mode = "k" })

---@class MdReadableMinimapGitState
---@field publish MdReadableMinimapPublish
---@field generation integer
---@field timer uv.uv_timer_t Debounce timer
---@field group integer Autocommand group id
---@field process? vim.SystemObj Running git command
---@field watcher? uv.uv_fs_poll_t Git index watcher
---@field root? string Repository top level
---@param index string Indexed text
---@param source string Buffer text
---@param row_count integer
---@return MdReadableMinimapItem[]
function M.diff(index, source, row_count)
  local items = {}
  local ok, hunks = pcall(vim.diff, index, source, { result_type = "indices", algorithm = "histogram" })
  if not ok then
    return items
  end
  ---@cast hunks integer[][]
  for _, hunk in ipairs(hunks) do
    local old_count, start, count = hunk[2], hunk[3], hunk[4]
    local row = count == 0 and math.max(0, math.min(start, row_count - 1)) or math.max(0, start - 1)
    items[#items + 1] = {
      start_row = row,
      end_row = row + math.max(1, count),
      kind = old_count == 0 and "add" or count == 0 and "delete" or "change",
    }
  end
  return items
end

---@param handle? uv.uv_timer_t|uv.uv_fs_poll_t
local function stop(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

---@param session MdReadableSession
---@param state MdReadableMinimapGitState
---@param generation integer
local function run(session, state, generation)
  if states[session] ~= state or session.closed or not vim.api.nvim_buf_is_valid(session.source_buf) then
    return
  end
  local buf, path = session.source_buf, vim.api.nvim_buf_get_name(session.source_buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local source = table.concat(lines, "\n") .. (vim.bo[buf].endofline and "\n" or "")
  ---@return boolean
  local function fresh()
    return states[session] == state
      and not session.closed
      and state.generation == generation
      and session.source_buf == buf
      and vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_get_changedtick(buf) == tick
  end
  ---@param items MdReadableMinimapItem[]
  local function publish(items)
    if fresh() then
      state.publish(session, "git", items)
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
    local relative = path:sub(#root + 2)
    if path:sub(1, #root + 1) ~= root .. "/" then
      publish({})
      return
    end
    local function compare()
      command({ "git", "-C", root, "show", ":" .. relative }, function(result)
        if result.code == 0 then
          publish(M.diff(result.stdout, source, #lines))
        else
          command({ "git", "-C", root, "ls-files", "--error-unmatch", "--", relative }, function(tracked)
            if tracked.code == 1 then
              publish(M.diff("", source, #lines))
            else
              publish({})
            end
          end)
        end
      end)
    end
    if state.root == root and state.watcher then
      compare()
      return
    end
    command({ "git", "-C", root, "rev-parse", "--path-format=absolute", "--git-path", "index" }, function(index_result)
      stop(state.watcher)
      state.watcher = nil
      if index_result.code == 0 then
        local index_path = index_result.stdout:gsub("[\r\n]+$", "")
        local watcher = vim.uv.new_fs_poll()
        ---@diagnostic disable-next-line: need-check-nil
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

---@param session MdReadableSession
function M.update(session)
  local state = states[session]
  if not state then
    return
  end
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

---@param session MdReadableSession
---@param publish MdReadableMinimapPublish
function M.attach(session, publish)
  M.close(session)
  local state = {
    publish = publish,
    generation = 0,
    timer = vim.uv.new_timer(),
    group = vim.api.nvim_create_augroup("MdReadableGit" .. session.id, { clear = true }),
  }
  states[session] = state
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost", "BufEnter" }, {
    group = state.group,
    buffer = session.source_buf,
    callback = function()
      M.update(session)
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = state.group,
    callback = function()
      M.update(session)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = state.group,
    buffer = session.source_buf,
    callback = function()
      publish(session, "git", {})
      M.close(session)
    end,
  })
  M.update(session)
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
  if state.group then
    pcall(vim.api.nvim_del_augroup_by_id, state.group)
  end
end

return M
