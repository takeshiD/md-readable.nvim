return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local git = require("md-readable.reader.git")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local ns = vim.api.nvim_create_namespace("MdReadableGit")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipeout!")
  end
  local function command(args)
    local result = vim.system(args, { text = true }):wait()
    assert(result.code == 0, result.stderr)
  end
  local function repository(lines)
    local dir = t.tempdir()
    t.write(dir .. "/doc.md", lines)
    command({ "git", "-C", dir, "init", "--quiet" })
    command({ "git", "-C", dir, "add", "doc.md" })
    return dir, dir .. "/doc.md"
  end
  local function open(path, opts)
    cleanup()
    api.setup(vim.tbl_deep_extend("force", {
      navigation = { auto_open = false },
      images = { enable = false },
      minimap = { enable = false },
      focus = { enable = false },
      watch = { enable = false },
      debounce = 0,
    }, opts or {}))
    vim.cmd("edit " .. path)
    return api.open("vert")
  end
  -- Display row (0-based) -> sign group.
  local function signs(s)
    local result = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(s.read_buf, ns, 0, -1, { details = true })) do
      result[mark[2]] = mark[4].sign_hl_group
    end
    return result
  end
  local function wait_signs(s, predicate)
    return vim.wait(5000, function()
      return predicate(signs(s))
    end, 20)
  end
  local function display_row(s, text)
    for index, line in ipairs(vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false)) do
      if line:find(text, 1, true) then
        return index - 1
      end
    end
  end

  t.test("hunks map to the display rows that show the changed source rows", function()
    t.eq({ { start_row = 1, end_row = 2, kind = "add" } }, git.diff("a\n", "a\nb\n", 2))
    t.eq({ { start_row = 1, end_row = 2, kind = "change" } }, git.diff("a\nb\n", "a\nc\n", 2))
    t.eq({ { start_row = 1, end_row = 2, kind = "delete" } }, git.diff("a\nb\nc\n", "a\nc\n", 2))
    -- Two source rows joined into one paragraph: only that display row.
    local lines = { "# Title", "", "first line", "second line", "", "after" }
    local rendered = render(parse(lines), { width = 40 })
    local projected = git.project(rendered, { { start_row = 3, end_row = 4, kind = "change" } })
    local rows = vim.tbl_keys(projected)
    t.eq(1, #rows)
    t.ok(rendered.lines[rows[1] + 1]:find("second line", 1, true), "the joined paragraph row")
    -- A change outranks an addition shown on the same display row.
    local both = git.project(rendered, {
      { start_row = 2, end_row = 3, kind = "add" },
      { start_row = 3, end_row = 4, kind = "change" },
    })
    t.eq("change", both[rows[1]])
  end)

  t.test("the reading view shows Git status of unsaved source edits in its sign column", function()
    local _, path = repository({
      "# Title",
      "",
      "keep",
      "",
      "edit me",
      "",
      "middle one",
      "",
      "middle two",
      "",
      "remove me",
      "",
      "end",
    })
    local s = open(path)
    t.eq("yes:1", vim.wo[s.read_win].signcolumn)
    t.ok(vim.wo[s.read_win].statuscolumn:find("%s", 1, true), "sign slot in the status column")
    t.ok(wait_signs(s, function(found)
      return vim.tbl_isempty(found)
    end))
    -- Bottom-up, so earlier row numbers stay valid.
    vim.api.nvim_buf_set_lines(s.source_buf, 10, 12, false, {})
    vim.api.nvim_buf_set_lines(s.source_buf, 4, 5, false, { "edited" })
    vim.api.nvim_buf_set_lines(s.source_buf, 2, 2, false, { "added", "" })
    local ok = wait_signs(s, function(found)
      return found[display_row(s, "added")] == "MdReadableGitAdd"
        and found[display_row(s, "edited")] == "MdReadableGitChange"
        and found[display_row(s, "end")] == "MdReadableGitDelete"
    end)
    t.ok(ok, vim.inspect(signs(s)))
    t.eq(nil, signs(s)[display_row(s, "keep")], "unchanged rows have no sign")
    -- Staging the edits empties the comparison with the index.
    vim.api.nvim_buf_call(s.source_buf, function()
      vim.cmd("silent write")
    end)
    command({ "git", "-C", vim.fs.dirname(path), "add", "doc.md" })
    vim.api.nvim_exec_autocmds("FocusGained", {})
    t.ok(
      wait_signs(s, function(found)
        return vim.tbl_isempty(found)
      end),
      "signs cleared after staging"
    )
    sessions.close(s)
    t.eq(nil, git.hunks(s), "closing stops comparing")
    cleanup()
  end)

  t.test("an untracked file is all additions; git.enable = false shows nothing", function()
    local dir = repository({ "tracked" })
    local path = dir .. "/new.md"
    t.write(path, { "# New", "", "text" })
    local s = open(path)
    t.ok(wait_signs(s, function(found)
      return found[display_row(s, "New")] == "MdReadableGitAdd" and found[display_row(s, "text")] == "MdReadableGitAdd"
    end))
    local off = open(path, { git = { enable = false } })
    t.eq("no", vim.wo[off.read_win].signcolumn)
    vim.wait(300, function()
      return false
    end)
    t.eq({}, signs(off))
    cleanup()
  end)
end
