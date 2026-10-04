return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local minimap = require("md-readable.minimap")
  local dir = t.tempdir()
  t.write(dir .. "/a.md", { "# Title", "", "Some text to read." })
  t.write(dir .. "/b.txt", { "plain" })
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipeout!")
  end
  local function open(opts)
    cleanup()
    api.setup(vim.tbl_deep_extend("force", {
      navigation = { auto_open = false },
      images = { enable = false },
      debounce = 0,
      width = 40,
      focus = { enable = false },
    }, opts or {}))
    vim.cmd("edit " .. dir .. "/a.md")
    vim.wo.number, vim.wo.wrap, vim.wo.statuscolumn = true, true, ""
    local s = api.open("current")
    t.ok(vim.wo[s.read_win].statuscolumn ~= "", "reading view is centered")
    return s
  end
  local function plain(label)
    local win = vim.api.nvim_get_current_win()
    t.eq("", vim.wo[win].statuscolumn, label .. ": centering margin")
    t.eq(true, vim.wo[win].wrap, label .. ": wrap")
    t.eq(true, vim.wo[win].number, label .. ": number")
    t.eq("", vim.wo[win].winbar, label .. ": winbar")
    t.eq(false, vim.wo[win].winfixwidth, label .. ": winfixwidth")
  end
  local function settle()
    vim.wait(50, function()
      return false
    end)
  end

  t.test("leaving the reading buffer by :edit restores the window options", function()
    local s = open({ minimap = { enable = false } })
    vim.cmd("edit " .. dir .. "/b.txt")
    settle()
    t.ok(s.closed, "session ends")
    plain(":edit")
    cleanup()
  end)

  t.test(":bdelete of the reading buffer returns to the source without E855", function()
    for _, command in ipairs({ "bdelete", "bwipeout" }) do
      for _, with_minimap in ipairs({ false, true }) do
        local label = command .. (with_minimap and " with minimap" or "")
        local s = open({ minimap = { enable = with_minimap } })
        local ok, err = pcall(vim.cmd, command)
        t.ok(ok, label .. ": " .. tostring(err))
        settle()
        t.ok(s.closed, label .. ": session ends")
        t.eq(dir .. "/a.md", vim.api.nvim_buf_get_name(0), label .. ": source shown")
        t.eq(1, #vim.api.nvim_tabpage_list_wins(0), label .. ": no stray window")
        plain(label)
      end
    end
    cleanup()
  end)

  t.test("the minimap does not inherit the reader's centering margin", function()
    local s = open()
    local state = assert(minimap.get(s))
    t.eq("", vim.wo[state.win].statuscolumn)
    cleanup()
  end)
end
