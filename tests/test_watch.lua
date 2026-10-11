return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  local function open(path, mode, opts)
    cleanup()
    api.setup(vim.tbl_deep_extend("force", {
      navigation = { auto_open = false },
      images = { enable = false },
      minimap = { enable = false },
      focus = { enable = false },
      debounce = 0,
    }, opts or {}))
    vim.cmd("silent! %bwipeout!")
    vim.cmd("edit " .. path)
    return api.open(mode)
  end
  local function reads(s, text, timeout)
    return vim.wait(timeout or 1000, function()
      return not s.closed
        and table.concat(vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false), "\n"):find(text, 1, true) ~= nil
    end, 20)
  end
  -- File timestamps have one-second granularity on some systems.
  local function later()
    vim.wait(1100, function()
      return false
    end)
  end

  t.test("a source reloaded from disk refreshes the view instead of closing it", function()
    for _, mode in ipairs({ "vert", "current" }) do
      local path = t.tempdir() .. "/doc.md"
      t.write(path, { "# Title", "", "old text" })
      local s = open(path, mode, { watch = { enable = false } })
      later()
      t.write(path, { "# Title", "", "changed on disk" })
      -- A plain :checktime skips hidden buffers (the source in "current" mode).
      vim.cmd("checktime " .. s.source_buf)
      t.ok(reads(s, "changed on disk"), mode .. ": view updated")
      t.ok(not s.closed, mode .. ": session stays open")
    end
    cleanup()
  end)

  t.test("watch.enable reloads changes made outside Neovim without :checktime", function()
    local dir = t.tempdir()
    local path = dir .. "/doc.md"
    t.write(path, { "# Title", "", "first" })
    local s = open(path, "vert")
    t.ok(s.watching, "the source file is watched")
    later()
    t.write(path, { "# Title", "", "written in place" })
    t.ok(reads(s, "written in place", 3000), "in-place write")
    later()
    -- Editors that save atomically replace the file by renaming.
    t.write(dir .. "/doc.md.tmp", { "# Title", "", "renamed over" })
    assert(vim.uv.fs_rename(dir .. "/doc.md.tmp", path))
    t.ok(reads(s, "renamed over", 3000), "atomic save")
    local watching = assert(s.watching)
    sessions.close(s)
    t.eq(nil, s.watching, "closing stops watching")
    t.ok(watching.timer:is_closing(), "timer released")
    cleanup()
  end)

  t.test("watch.enable = false leaves external changes until Neovim checks", function()
    local path = t.tempdir() .. "/doc.md"
    t.write(path, { "# Title", "", "first" })
    local s = open(path, "vert", { watch = { enable = false } })
    t.eq(nil, s.watching)
    later()
    t.write(path, { "# Title", "", "unseen" })
    t.ok(not reads(s, "unseen", 600), "no automatic reload")
    cleanup()
  end)
end
