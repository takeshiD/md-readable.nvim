return function(t)
  local cache = require("md-readable.image.cache")
  local capabilities = require("md-readable.image.capabilities")
  local convert = require("md-readable.image.convert")
  local download = require("md-readable.image.download")
  local display = require("md-readable.image.display")
  local provider = require("md-readable.providers.image")
  local mermaid = require("md-readable.providers.mermaid")
  local png =
    vim.base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Z1cAAAAASUVORK5CYII=")
  local function binary(path, data)
    local fd = assert(vim.uv.fs_open(path, "w", 420))
    assert(vim.uv.fs_write(fd, data, 0))
    assert(vim.uv.fs_close(fd))
  end
  local next_id = 2000
  local function session(dir)
    next_id = next_id + 1
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = { "# Picture", "", "", "", "", "", "", "", "", "Following text" }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 0, col = 0, width = 40, height = 15 })
    vim.cmd.redraw()
    local s = {
      id = next_id,
      source_buf = buf,
      read_buf = buf,
      read_win = win,
      document = { path = dir .. "/source.md" },
      generation = 1,
      rendered = { lines = lines, images = {} },
      config = { images = { cache_dir = dir, remote = false }, mermaid = {} },
    }
    s.cleanup = function()
      provider.close(s)
      mermaid.close(s)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    return s
  end

  t.test("image capability detection is explicit about supported UI and fallback", function()
    t.eq(true, capabilities.detect({ TERM_PROGRAM = "kitty" }, true))
    t.eq(true, capabilities.detect({ TERM_PROGRAM = "ghostty" }, true))
    t.eq(true, capabilities.detect({ KITTY_WINDOW_ID = "1" }, true))
    t.eq(true, capabilities.detect({ GHOSTTY_RESOURCES_DIR = "/usr/share/ghostty", TMUX = "/tmp/tmux" }, true))
    t.eq(false, capabilities.detect({ TERM_PROGRAM = "ghostty" }, false))
    t.eq(
      { false, "WezTerm does not support Kitty Unicode placeholders" },
      { capabilities.detect({ TERM_PROGRAM = "WezTerm" }, true) }
    )
    t.eq(false, capabilities.detect({ TERM_PROGRAM = "unknown" }, true))
  end)

  t.test("image file identity changes on contents and path decoding stays local", function()
    local dir = t.tempdir()
    local path = dir .. "/space ; image.png"
    binary(path, png)
    local first = cache.identity(path)
    binary(path, png .. "x")
    t.ok(first ~= cache.identity(path))
    local s = session(dir)
    t.eq(path, provider.resolve(s, "space%20%3B%20image.png"))
    local remote, is_remote = provider.resolve(s, "https://example.test/a.png")
    t.eq("https://example.test/a.png", remote)
    t.eq(true, is_remote)
    t.eq(nil, provider.resolve(s, "javascript:alert(1)"))
    s.cleanup()
  end)

  t.test("PNG conversion pass-through and read limits are asynchronous", function()
    local dir = t.tempdir()
    local path = dir .. "/picture.png"
    binary(path, png)
    local completed, result
    convert.ensure(path, { cache_dir = dir }, function(value)
      result = value
      completed = true
    end)
    t.ok(vim.wait(1000, function()
      return completed
    end))
    t.eq(path, result)
    local err
    convert.ensure(path, { max_bytes = 1 }, function(value, message)
      t.eq(nil, value)
      err = message
    end)
    t.eq("image exceeds max_bytes", err)
  end)

  t.test("remote image denial never starts a process", function()
    local original = vim.system
    local called, error_message = false, nil
    vim.system = function()
      called = true
      error("network must not run")
    end
    local ok, err = pcall(function()
      download.fetch("https://example.test/image.png", { remote = false }, function(_, message)
        error_message = message
      end)
    end)
    vim.system = original
    t.ok(ok, err)
    t.eq(false, called)
    t.eq("remote images are not allowed", error_message)
  end)

  t.test("remote image fetch confines schemes and uses argv, permission and byte limits", function()
    local original = vim.system
    local args, command_opts, completion
    vim.system = function(argv, options, callback)
      args, command_opts, completion = argv, options, callback
      return { kill = function() end }
    end
    local dir = t.tempdir()
    local callback_path
    local ok, err = pcall(function()
      download.fetch(
        "https://example.test/a.png?x=$(touch bad)",
        { remote = true, max_bytes = 1234, cache_dir = dir },
        function(path)
          callback_path = path
        end
      )
      t.eq("curl", args[1])
      t.eq("https://example.test/a.png?x=$(touch bad)", args[#args])
      t.ok(vim.tbl_contains(args, "--proto-redir"))
      t.ok(vim.tbl_contains(args, "1234"))
      t.eq(30000, command_opts.timeout)
      local output_index
      for i, value in ipairs(args) do
        if value == "--output" then
          output_index = i + 1
        end
      end
      binary(args[output_index], png)
      completion({ code = 0, stderr = "" })
      t.ok(vim.wait(1000, function()
        return callback_path ~= nil
      end))
    end)
    vim.system = original
    t.ok(ok, err)
  end)

  t.test("Kitty PNG transport chunks payload and creates a placeholder placement", function()
    local width, height = display.dimensions(png)
    t.eq(1, width)
    t.eq(1, height)
    t.eq(nil, display.dimensions("not png"))
    local packet = display.protocol(100, string.rep("a", 7000), 10, 5)
    t.ok(packet:find("\27_Ga=t,f=100,t=d,i=100,q=2,m=1;", 1, true), "first chunk")
    t.ok(packet:find("\27_Gm=0;", 1, true), "last chunk")
    local placement = "\27_Ga=p,U=1,i=100,c=10,r=5,C=1,q=2\27\\"
    t.eq(placement, packet:sub(-#placement), "virtual placement, no cursor movement")
    t.ok(not packet:find("\27[s", 1, true), "nothing is drawn at screen coordinates")
    -- One placeholder cell per column, each U+10EEEE with row and column diacritics.
    local row = display.placeholders(2, 3)
    t.eq(3, vim.fn.strdisplaywidth(row))
    t.eq(9, vim.fn.strchars(row))
    t.eq(0x10EEEE, vim.fn.char2nr(vim.fn.strcharpart(row, 0, 1)))
    t.eq(0x030E, vim.fn.char2nr(vim.fn.strcharpart(row, 1, 1)), "row 2")
    t.eq(0x030E, vim.fn.char2nr(vim.fn.strcharpart(row, 8, 1)), "column 3")
  end)

  t.test("images still shown are deleted when Neovim exits", function()
    local dir = t.tempdir()
    local path = dir .. "/image.png"
    binary(path, png)
    local s = session(dir)
    local original, tmux = vim.api.nvim_ui_send, vim.env.TMUX
    local sent, shown = {}, {}
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    local ok, err = pcall(function()
      for _, row in ipairs({ 1, 6 }) do
        display.show(path, s.read_win, { row = row, height = 4, width = 20 }, {}, function(id)
          shown[#shown + 1] = id
        end)
      end
      t.ok(vim.wait(1000, function()
        return #shown == 2
      end))
      sent = {}
      vim.api.nvim_exec_autocmds("VimLeavePre", { group = "MdReadableImageDisplay" })
      for _, id in ipairs(shown) do
        t.ok(
          vim.iter(sent):any(function(data)
            return data:find("a=d,d=I,i=" .. id, 1, true) ~= nil
          end),
          "image " .. id .. " deleted"
        )
      end
      sent = {}
      display.delete_all()
      t.eq({}, sent, "nothing left to delete")
    end)
    vim.api.nvim_ui_send, vim.env.TMUX = original, tmux
    s.cleanup()
    t.ok(ok, err)
  end)

  t.test("placeholders fill the reserved rows, keep the text, and go with their image", function()
    local dir = t.tempdir()
    local path = dir .. "/image.png"
    binary(path, png)
    local s = session(dir)
    local original, tmux = vim.api.nvim_ui_send, vim.env.TMUX
    local sent, shown = {}, false
    vim.env.TMUX = nil
    vim.api.nvim_ui_send = function(data)
      sent[#sent + 1] = data
    end
    local ns = vim.api.nvim_create_namespace("MdReadableImages")
    local ok, err = pcall(function()
      t.eq({ 8, 4 }, { display.size(s.read_win, { row = 1, height = 4, width = 20 }, 1, 1) })
      local _, cancel = display.show(path, s.read_win, { row = 1, height = 4, width = 20 }, {}, function(id)
        shown = id
      end)
      t.ok(vim.wait(1000, function()
        return shown
      end))
      t.ok(sent[1]:find("a=t,f=100", 1, true))
      t.ok(sent[1]:find("a=p,U=1,i=" .. shown .. ",c=8,r=4", 1, true))
      local marks = vim.api.nvim_buf_get_extmarks(s.read_buf, ns, 0, -1, { details = true })
      t.eq(
        { 1, 2, 3, 4 },
        vim.tbl_map(function(mark)
          return mark[2]
        end, marks)
      )
      local details = marks[1][4]
      t.eq("win_col", details.virt_text_pos, "overlay at a fixed text column")
      t.eq(0, details.virt_text_win_col)
      t.eq("MdReadableImage" .. shown, details.virt_text[1][2])
      t.eq(shown, vim.api.nvim_get_hl(0, { name = "MdReadableImage" .. shown }).fg, "color names the image")
      cancel()
      t.ok(sent[#sent]:find("a=d,d=I,i=" .. shown, 1, true))
      t.eq({}, vim.api.nvim_buf_get_extmarks(s.read_buf, ns, 0, -1, {}))
      t.eq(s.rendered.lines, vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false))
    end)
    vim.api.nvim_ui_send, vim.env.TMUX = original, tmux
    s.cleanup()
    t.ok(ok, err)
  end)

  t.test("provider cancels stale conversions and preserves original fallback text", function()
    local dir = t.tempdir()
    local path = dir .. "/image.png"
    binary(path, png)
    local s = session(dir)
    s.rendered.images = { { kind = "image", path = "image.png", row = 1, source_row = 0, height = 4 } }
    local cap, ensure, show = capabilities.get, convert.ensure, display.show
    local callbacks, cancelled, displays = {}, 0, 0
    capabilities.get = function()
      return true
    end
    convert.ensure = function(_, _, callback)
      callbacks[#callbacks + 1] = callback
      return function()
        cancelled = cancelled + 1
      end
    end
    display.show = function()
      displays = displays + 1
      return 1, function() end
    end
    local ok, err = pcall(function()
      provider.update(s)
      t.eq(1, #callbacks)
      s.generation = 2
      provider.update(s)
      t.eq(1, cancelled)
      callbacks[1](path)
      t.eq(0, displays)
      callbacks[2](path)
      t.eq(1, displays)
      provider.close(s)
      t.eq(2, cancelled)
      t.eq(s.rendered.lines, vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false))
    end)
    capabilities.get, convert.ensure, display.show = cap, ensure, show
    s.cleanup()
    t.ok(ok, err)
  end)

  t.test("Mermaid uses installed executable with safe arguments, caches settings, cancels jobs", function()
    local dir = t.tempdir()
    local fixture = dir .. "/fixture.png"
    binary(fixture, png)
    local script = dir .. "/fake-mmdc"
    t.write(script, {
      "#!/bin/sh",
      'while [ "$#" -gt 0 ]; do',
      '  case "$1" in --output) shift; output="$1";; esac',
      "  shift",
      "done",
      'cp "$MD_READABLE_TEST_PNG" "$output"',
    })
    assert(vim.uv.fs_chmod(script, 493))
    local previous = vim.env.MD_READABLE_TEST_PNG
    vim.env.MD_READABLE_TEST_PNG = fixture
    local s = session(dir)
    s.config.mermaid.command = script
    local ok, err = pcall(function()
      t.eq(nil, mermaid.command("a", "b", { command = "npx" }))
      t.eq(nil, mermaid.command("a", "b", { command = "/definitely/missing/mmdc" }))
      local result
      mermaid.render(s, { code = "flowchart LR\nA --> B" }, function(path)
        result = path
      end)
      t.ok(vim.wait(2000, function()
        return result ~= nil
      end))
      t.ok(vim.uv.fs_stat(result))
      local cached
      mermaid.render(s, { code = "flowchart LR\nA --> B" }, function(path)
        cached = path
      end)
      t.eq(result, cached)
      s.config.mermaid.theme = "dark"
      local different
      mermaid.render(s, { code = "flowchart LR\nA --> B" }, function(path)
        different = path
      end)
      t.ok(vim.wait(2000, function()
        return different ~= nil
      end))
      t.ok(different ~= result)
      local called = false
      local cancel = mermaid.render(s, { code = "flowchart LR\nC --> D" }, function()
        called = true
      end)
      cancel()
      vim.wait(100, function()
        return false
      end)
      t.eq(false, called)
    end)
    vim.env.MD_READABLE_TEST_PNG = previous
    s.cleanup()
    t.ok(ok, err)
  end)

  t.test("mermaid.no_sandbox passes a puppeteer config that disables the sandbox", function()
    local plain = assert(mermaid.command("in.mmd", "out.png", { command = "sh" }))
    t.ok(not vim.tbl_contains(plain, "--puppeteerConfigFile"))
    local args = assert(mermaid.command("in.mmd", "out.png", { command = "sh", no_sandbox = true }))
    local index = assert(vim.iter(ipairs(args)):find(function(_, value)
      return value == "--puppeteerConfigFile"
    end))
    local config = args[index + 1]
    t.eq({ args = { "--no-sandbox" } }, vim.json.decode(table.concat(vim.fn.readfile(config), "\n")))
  end)

  t.test("Mermaid diagrams are generated sharp and get rows that fit the body width", function()
    local args = assert(mermaid.command("in.mmd", "out.png", { command = "sh" }))
    t.eq(
      "3",
      args[assert(vim.iter(ipairs(args)):find(function(_, value)
        return value == "--scale"
      end)) + 1]
    )
    local function header(width, height)
      local function be32(n)
        return string.char(
          math.floor(n / 16777216) % 256,
          math.floor(n / 65536) % 256,
          math.floor(n / 256) % 256,
          n % 256
        )
      end
      return "\137PNG\r\n\26\n\0\0\0\13IHDR" .. be32(width) .. be32(height) .. string.rep("\0", 16)
    end
    local dir = t.tempdir()
    local script = dir .. "/fake-mmdc"
    t.write(script, {
      "#!/bin/sh",
      'while [ "$#" -gt 0 ]; do',
      '  case "$1" in --output) shift; output="$1";; esac',
      "  shift",
      "done",
      'cp "$MD_READABLE_TEST_PNG" "$output"',
    })
    assert(vim.uv.fs_chmod(script, 493))
    local previous = vim.env.MD_READABLE_TEST_PNG
    local s = session(dir)
    s.config.mermaid = { command = script, max_rows = 25 }
    local ok, err = pcall(function()
      for _, case in ipairs({ { "wide", 400, 100, 5 }, { "tall", 100, 400, 25 } }) do
        local fixture = dir .. "/" .. case[1] .. ".png"
        binary(fixture, header(case[2], case[3]))
        vim.env.MD_READABLE_TEST_PNG = fixture
        local descriptor = { kind = "mermaid", code = "graph " .. case[1], width = 40 }
        t.eq(nil, mermaid.rows(s, descriptor), case[1] .. ": nothing generated yet")
        local done
        mermaid.render(s, descriptor, function(path)
          done = path
        end)
        t.ok(vim.wait(2000, function()
          return done ~= nil
        end))
        -- Cells are twice as tall as wide: ceil(40 * h / (2 * w)), at most max_rows.
        t.eq(case[4], mermaid.rows(s, descriptor), case[1])
      end
    end)
    vim.env.MD_READABLE_TEST_PNG = previous
    s.cleanup()
    t.ok(ok, err)
  end)

  t.test("a numeric reservation sets the media rows", function()
    local parse = require("md-readable.document.parser").parse
    local render = require("md-readable.reader.render").render
    local value = render(parse({ "```mermaid", "graph TD", "```", "after" }), {
      media = {
        image_height = 4,
        reserve = function()
          return 7
        end,
      },
    })
    t.eq(7, value.images[1].height)
    t.eq("after", value.lines[#value.lines])
    -- Inside the code panel: the diagram rows, then the panel's bottom row.
    t.eq(7 + 1, #value.lines - 1 - value.images[1].row)
  end)
end
