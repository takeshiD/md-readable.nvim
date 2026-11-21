return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local minimap = require("md-readable.minimap")

  t.test("removed minimap options are ignored without changing reader Git settings", function()
    local opts = { minimap = { git = { enable = true }, diagnostic = { enable = true } }, git = { enable = false } }
    local config = require("md-readable.config").setup(opts)
    t.eq(nil, config.minimap.git)
    t.eq(nil, config.minimap.diagnostic)
    t.eq(false, config.git.enable)
    t.eq(true, opts.minimap.git.enable, "setup does not mutate the user's options")
  end)

  t.test("minimap lifecycle needs no Git processes, index watchers or diagnostic subscriptions", function()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
    local dir = t.tempdir()
    local path = dir .. "/doc.md"
    local lines = {}
    for i = 1, 200 do
      lines[#lines + 1] = "# Heading " .. i
      lines[#lines + 1] = ""
    end
    t.write(path, lines)
    local result = vim.system({ "git", "init", "--quiet", dir }, { text = true }):wait()
    t.eq(0, result.code, result.stderr)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local source = vim.api.nvim_get_current_buf()
    local ns = vim.api.nvim_create_namespace("MdReadableTestNativeDiagnostics")
    local diagnostic = { lnum = 1, col = 0, message = "native error", severity = vim.diagnostic.severity.ERROR }
    vim.diagnostic.set(ns, source, { diagnostic })
    local system, poll, autocmd = vim.system, vim.uv.new_fs_poll, vim.api.nvim_create_autocmd
    local calls = { git = 0, poll = 0, diagnostic = 0 }
    vim.system = function(args, ...)
      if args[1] == "git" then
        calls.git = calls.git + 1
      end
      return system(args, ...)
    end
    vim.uv.new_fs_poll = function(...)
      calls.poll = calls.poll + 1
      return poll(...)
    end
    vim.api.nvim_create_autocmd = function(events, ...)
      if vim.tbl_contains(type(events) == "table" and events or { events }, "DiagnosticChanged") then
        calls.diagnostic = calls.diagnostic + 1
      end
      return autocmd(events, ...)
    end
    local ok, err = xpcall(function()
      for _, mode in ipairs({ "braille", "ascii" }) do
        api.setup({
          navigation = { enable = false },
          images = { enable = false },
          watch = { enable = false },
          git = { enable = false }, -- Independent reading sign-column provider.
          minimap = { enable = true, mode = mode, follow = false },
          debounce = 0,
        })
        local s = assert(api.open("vert"))
        local state = assert(minimap.get(s))
        for _, line in ipairs(state.rendered.lines) do
          t.eq(vim.api.nvim_win_get_width(state.win), vim.fn.strdisplaywidth(line), "no annotation lanes")
        end
        vim.diagnostic.set(ns, source, { diagnostic })
        vim.api.nvim_exec_autocmds("FocusGained", {})
        vim.api.nvim_buf_set_lines(source, 1, 2, false, { "edited" })
        s:refresh()
        minimap.update(s)
        minimap.focus(s)
        local row = #state.rendered.lines
        local display = state.rendered.mini_to_display[row]
        vim.api.nvim_win_set_cursor(state.win, { row, 0 })
        local enter = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
        vim.api.nvim_feedkeys(enter, "xt", false)
        t.eq(s.read_win, vim.api.nvim_get_current_win(), "Enter returns to the document")
        t.eq(display + 1, vim.api.nvim_win_get_cursor(s.read_win)[1])
        minimap.update(s)
        local marks = vim.api.nvim_buf_get_extmarks(
          state.buf,
          vim.api.nvim_get_namespaces().MdReadableMinimap,
          0,
          -1,
          { details = true }
        )
        local current
        for _, mark in ipairs(marks) do
          if mark[4].line_hl_group == "MdReadableMinimapCurrent" then
            current = mark[2]
          end
        end
        t.eq(state.rendered.display_to_mini[display + 1], current, "current position remains highlighted")
        t.eq(false, minimap.toggle(s))
        t.ok(not vim.api.nvim_buf_is_valid(state.buf))
        t.ok(minimap.toggle(s), "reopens")
        -- Allow debounced providers to run, if one is accidentally attached.
        vim.wait(200, function()
          return false
        end)
        sessions.close(s)
      end
      t.eq({ git = 0, poll = 0, diagnostic = 0 }, calls)
      t.eq("native error", vim.diagnostic.get(source, { namespace = ns })[1].message)
    end, debug.traceback)
    vim.system, vim.uv.new_fs_poll, vim.api.nvim_create_autocmd = system, poll, autocmd
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.diagnostic.reset(ns, source)
    t.ok(ok, err)
  end)
end
