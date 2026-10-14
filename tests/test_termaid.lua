return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local termaid = require("md-readable.providers.termaid")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local source = { "before", "", "```mermaid", "graph LR", "  A --> B", "```", "after" }
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipeout!")
  end
  -- A stand-in for termaid: prints a fixed diagram, logs its arguments.
  local function fake(dir)
    local script = dir .. "/fake-termaid"
    t.write(script, {
      "#!/bin/sh",
      'echo "$*" >> "' .. dir .. '/calls"',
      "cat > /dev/null",
      "echo '┌───┐   ┌───┐'",
      "echo '│ A ├──►│ B │'",
      "echo '└───┘   └───┘'",
    })
    assert(vim.uv.fs_chmod(script, 493))
    return script
  end
  local function calls(dir)
    return vim.fn.filereadable(dir .. "/calls") == 1 and vim.fn.readfile(dir .. "/calls") or {}
  end

  t.test("text diagrams replace the Mermaid code inside the code panel", function()
    local value = render(parse(source), {
      width = 30,
      diagram = function(code, width)
        t.eq("graph LR\n  A --> B", code)
        t.eq(28, width, "the panel's inner width")
        return { "[A]-->[B]" }
      end,
    })
    local text = table.concat(value.lines, "\n")
    t.ok(text:find(" [A]-->[B]", 1, true), "diagram inside the panel")
    t.ok(not text:find("A --> B", 1, true), "code replaced")
    t.eq(0, #value.images, "no image reserved")
    local fallback = render(parse(source), {
      width = 30,
      diagram = function()
        return nil
      end,
    })
    t.ok(table.concat(fallback.lines, "\n"):find("A --> B", 1, true), "code when termaid cannot draw it")
    t.eq(0, #fallback.images, "the text renderer never falls back to images")
  end)

  t.test("termaid runs once per diagram, width and arguments", function()
    local dir = t.tempdir()
    local opts =
      { renderer = "termaid", command = fake(dir), args = { "--x" }, termaid_opts = { ascii = true, gap = 1 } }
    local lines = assert(termaid.render("graph LR\nA-->B", 40, opts))
    t.eq("│ A ├──►│ B │", lines[2])
    t.eq({ "--x --ascii --gap 1 --width 40" }, calls(dir), "args, then termaid_opts, then the width")
    termaid.render("graph LR\nA-->B", 40, opts)
    t.eq(1, #calls(dir), "cached")
    termaid.render("graph LR\nA-->B", 30, opts)
    t.eq(2, #calls(dir), "another width runs again")
    local missing, err = termaid.render("graph LR\nA-->B", 40, { command = dir .. "/none" })
    t.eq(nil, missing)
    t.ok(err:find("install termaid", 1, true))
  end)

  t.test("mermaid.renderer = termaid draws text diagrams in the reading view", function()
    local dir = t.tempdir()
    t.write(dir .. "/doc.md", source)
    for _, case in ipairs({ { fake(dir), true }, { dir .. "/missing-termaid", false } }) do
      cleanup()
      api.setup({
        navigation = { auto_open = false },
        minimap = { enable = false },
        focus = { enable = false },
        git = { enable = false },
        watch = { enable = false },
        images = { enable = false },
        debounce = 0,
        mermaid = { renderer = "termaid", command = case[1] },
      })
      vim.cmd("edit " .. dir .. "/doc.md")
      local s = api.open("vert")
      local text = table.concat(vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false), "\n")
      if case[2] then
        t.ok(text:find("│ A ├──►│ B │", 1, true), "diagram shown without image support")
      else
        t.ok(text:find("A --> B", 1, true), "code without termaid")
        local reported = table.concat(require("md-readable.providers.image").errors(s), "\n")
        t.ok(reported:find("install termaid", 1, true), "reported in diagnostics: " .. reported)
      end
    end
    local ok, err = pcall(api.setup, { mermaid = { renderer = "kroki" } })
    t.ok(not ok and err:find('mermaid.renderer must be "mmdc" or "termaid"', 1, true), tostring(err))
    ok, err = pcall(api.setup, { mermaid = { termaid_opts = { color = true } } })
    t.ok(not ok and err:find("mermaid.termaid_opts.color is not a termaid option", 1, true), tostring(err))
    cleanup()
  end)
end
