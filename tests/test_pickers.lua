return function(t)
  local core = require("md-readable.integrations.preview")
  local function fixture(name, lines)
    local path = t.tempdir() .. "/" .. name
    t.write(path, lines)
    return path
  end
  local function window(fn)
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(
      buf,
      false,
      { relative = "editor", row = 1, col = 1, width = 50, height = 12, style = "minimal" }
    )
    local ok, err = xpcall(function()
      fn(buf, win)
    end, debug.traceback)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    if not ok then
      error(err)
    end
  end
  local function wait(check)
    t.ok(vim.wait(3000, check, 10), "preview callback timed out")
  end
  t.test("picker modules load without installing picker dependencies", function()
    t.ok(require("md-readable.integrations.telescope").previewer)
    t.ok(require("md-readable.integrations.snacks").preview)
    t.eq("markdown", core.kind("UPPER.MDX"))
    t.eq("image", core.kind("test.webp"))
    t.eq(nil, core.kind("test.lua"))
  end)
  t.test("async preview renders real Markdown and follows each same-file grep row", function()
    local path = fixture("document.md", { "# Title", "one", "two", "three", "four", "five" })
    window(function(buf, win)
      local engine = core.new({ debounce = 0, config = { images = { enabled = false } } })
      engine:show(path, buf, win, { 2, 0 })
      wait(function()
        return engine.session ~= nil
      end)
      t.eq("Title", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
      t.eq(3, vim.api.nvim_win_get_cursor(win)[1])
      local source_buf = engine.session.source_buf
      engine:show(path, buf, win, { 5, 0 })
      wait(function()
        return engine.session ~= nil
      end)
      t.eq({ 3, 14 }, vim.api.nvim_win_get_cursor(win))
      t.ok(not vim.api.nvim_buf_is_valid(source_buf))
      source_buf = engine.session.source_buf
      engine:close()
      t.ok(not vim.api.nvim_buf_is_valid(source_buf))
    end)
  end)
  t.test("rapid candidate changes discard old delayed work", function()
    local first = fixture("first.md", { "# First" })
    local second = fixture("second.md", { "# Second" })
    window(function(buf, win)
      local engine = core.new({ debounce = 20, config = { images = { enabled = false } } })
      engine:show(first, buf, win)
      engine:show(second, buf, win)
      wait(function()
        return engine.session ~= nil
      end)
      t.eq(second, engine.session.document.path)
      t.eq("Second", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
      engine:close()
    end)
  end)
  t.test("closing preview before pending reads never mutates picker buffers", function()
    local path = fixture("pending.md", { "# Pending" })
    window(function(buf, win)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "untouched" })
      local engine = core.new({ debounce = 30 })
      engine:show(path, buf, win)
      engine:close()
      vim.wait(80, function()
        return false
      end, 10)
      t.eq({ "untouched" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      t.eq(nil, engine.session)
    end)
  end)
  t.test("unsupported files and oversized Markdown call original fallback", function()
    window(function(buf, win)
      local fallback = 0
      local engine = core.new({ debounce = 0, max_bytes = 2 })
      t.eq(
        false,
        engine:show("source.lua", buf, win, nil, function()
          fallback = fallback + 1
        end)
      )
      t.eq(1, fallback)
      engine:show(fixture("large.md", { "# too big" }), buf, win, nil, function()
        fallback = fallback + 1
      end)
      wait(function()
        return fallback == 2
      end)
      engine:close()
    end)
  end)
  t.test("preview prefers unsaved loaded source without modifying it", function()
    local path = fixture("unsaved.md", { "# disk" })
    local source = vim.fn.bufadd(path)
    vim.fn.bufload(source)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "# unsaved" })
    window(function(buf, win)
      local engine = core.new({ debounce = 0 })
      engine:show(path, buf, win)
      wait(function()
        return engine.session ~= nil
      end)
      t.eq("unsaved", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
      t.eq({ "# unsaved" }, vim.api.nvim_buf_get_lines(source, 0, -1, false))
      engine:close()
    end)
    vim.api.nvim_buf_delete(source, { force = true })
  end)
  t.test("media session updates and closes independently from normal reader sessions", function()
    local previous, updated, closed = package.loaded["md-readable.providers.image"], 0, 0
    package.loaded["md-readable.providers.image"] = {
      capabilities = function()
        return true
      end,
      update = function(session)
        updated = updated + 1
        t.eq("image", session.rendered.images[1].kind)
      end,
      close = function()
        closed = closed + 1
      end,
    }
    local ok, err = xpcall(function()
      window(function(buf, win)
        local engine = core.new({ debounce = 0, config = { images = { enabled = true, height = 3 } } })
        engine:show("/tmp/example.png", buf, win)
        wait(function()
          return updated == 1
        end)
        t.eq(3, engine.session.rendered.images[1].height)
        engine:close()
        t.eq(1, closed)
      end)
    end, debug.traceback)
    package.loaded["md-readable.providers.image"] = previous
    if not ok then
      error(err)
    end
  end)
  -- Installed picker integration is optional locally. CI also exercises the
  -- dependency-free engine above; these run when the real plugins are present.
  local lazy = vim.fn.expand("~/.local/share/nvim/lazy/")
  if vim.fn.isdirectory(lazy .. "telescope.nvim") == 1 and vim.fn.isdirectory(lazy .. "plenary.nvim") == 1 then
    t.test("real Telescope buffer preview lifecycle follows grep positions", function()
      vim.opt.runtimepath:append(lazy .. "plenary.nvim")
      vim.opt.runtimepath:append(lazy .. "telescope.nvim")
      require("telescope").setup({})
      local path = fixture("telescope.md", { "# Telescope", "second", "third", "fourth" })
      window(function(_, win)
        local previewer = require("md-readable.integrations.telescope").previewer({ debounce = 0 })
        local status = { layout = { preview = { winid = win } } }
        previewer:preview({ filename = path, lnum = 2 }, status)
        wait(function()
          local b = vim.api.nvim_win_get_buf(win)
          return vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == "Telescope"
        end)
        t.eq(3, vim.api.nvim_win_get_cursor(win)[1])
        local previous_buf = previewer.state.bufnr
        previewer:preview({ filename = path, lnum = 4 }, status)
        wait(function()
          return previewer.state.bufnr ~= previous_buf and vim.deep_equal(vim.api.nvim_win_get_cursor(win), { 3, 13 })
        end)
        previewer:teardown()
      end)
    end)
  end
  if vim.fn.isdirectory(lazy .. "snacks.nvim") == 1 then
    t.test("real Snacks path and default fallback cooperate with preview callback", function()
      vim.opt.runtimepath:append(lazy .. "snacks.nvim")
      _G.Snacks = require("snacks")
      local path = fixture("snacks.md", { "# Snacks", "two", "three" })
      window(function(buf, win)
        local controller = {
          reset = function()
            vim.bo[buf].modifiable = true
          end,
          set_title = function() end,
          minimal = function() end,
        }
        local callback = require("md-readable.integrations.snacks").preview({ debounce = 0 })
        local context = { preview = controller, buf = buf, win = win, item = { file = path, pos = { 2, 0 } } }
        callback(context)
        wait(function()
          return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "Snacks"
        end)
        t.eq(3, vim.api.nvim_win_get_cursor(win)[1])
        context.item.pos = { 3, 0 }
        callback(context)
        wait(function()
          return vim.deep_equal(vim.api.nvim_win_get_cursor(win), { 3, 4 })
        end)
      end)
    end)
    t.test("actual Snacks picker opens renders and closes its owned preview", function()
      vim.opt.runtimepath:append(lazy .. "snacks.nvim")
      _G.Snacks = require("snacks")
      local path = fixture("full-snacks.md", { "# Full Snacks", "two", "three", "four" })
      local picker = Snacks.picker({
        items = { { file = path, text = "first", pos = { 2, 0 } }, { file = path, text = "second", pos = { 4, 0 } } },
        format = "file",
        preview = require("md-readable.integrations.snacks").preview({ debounce = 0 }),
        layout = { preset = "default", preview = true },
        focus = "list",
        show_delay = 0,
      })
      local ok, err = xpcall(function()
        wait(function()
          local p = picker.preview
          return p
            and p.win
            and p.win.buf
            and vim.api.nvim_buf_is_valid(p.win.buf)
            and vim.api.nvim_buf_get_lines(p.win.buf, 0, 1, false)[1] == "Full Snacks"
        end)
        picker.list:move(2, true, true)
        picker:show_preview()
        wait(function()
          return vim.deep_equal(vim.api.nvim_win_get_cursor(picker.preview.win.win), { 3, 10 })
        end)
      end, debug.traceback)
      picker:close()
      if not ok then
        error(err)
      end
    end)
  end
end
