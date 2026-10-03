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
    t.eq(true, capabilities.detect({ TERM_PROGRAM = "WezTerm" }, true))
    t.eq(true, capabilities.detect({ TERM_PROGRAM = "ghostty" }, true))
    t.eq(true, capabilities.detect({ KITTY_WINDOW_ID = "1" }, true))
    t.eq(false, capabilities.detect({ TERM_PROGRAM = "WezTerm" }, false))
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

  t.test("Kitty PNG transport chunks payload, crops explicitly and restores cursor", function()
    local width, height = display.dimensions(png)
    t.eq(1, width)
    t.eq(1, height)
    t.eq(nil, display.dimensions("not png"))
    local data = string.rep("a", 7000)
    local packet =
      display.protocol(100, data, { row = 3, col = 4, columns = 10, rows = 5, x = 0, y = 2, width = 10, height = 8 })
    t.ok(packet:find("a=T,f=100,t=d,i=100,p=100,c=10,r=5,x=0,y=2,w=10,h=8,C=1,q=2,m=1", 1, true))
    t.ok(packet:find("\27_Gm=0;", 1, true))
    t.eq("\27[s\27[3;4H", packet:sub(1, 9))
    t.eq("\27[u", packet:sub(-3))
  end)

  t.test("inline placements occupy reserved rows, preserve text, and delete only their ID", function()
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
    local ok, err = pcall(function()
      local geometry = display.geometry(s.read_win, { row = 1, height = 4, width = 20 }, 1, 1)
      t.ok(geometry)
      t.eq(4, geometry.rows)
      t.eq(8, geometry.columns)
      local _, cancel = display.show(path, s.read_win, { row = 1, height = 4, width = 20 }, {}, function(id)
        shown = id
      end)
      t.ok(vim.wait(1000, function()
        return shown
      end))
      t.ok(sent[1]:find("a=T", 1, true))
      cancel()
      t.ok(sent[#sent]:find("a=d,d=I,i=" .. shown, 1, true))
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
end
