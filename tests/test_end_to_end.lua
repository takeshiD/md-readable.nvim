return function(t)
  local api = require("md-readable")
  local Sessions = require("md-readable.reader.session")
  local Navigation = require("md-readable.ui.navigation")
  local Resolver = require("md-readable.navigation.resolver")
  local function fixture(extra)
    local root = t.tempdir()
    local files = {
      ["book.toml"] = { "[book]", 'title = "Integration book"', 'src = "chapters"' },
      ["chapters/SUMMARY.md"] = {
        "# Summary",
        "- [Introduction](intro.md)",
        "- [Second](second.md)",
        "- [Last](last.md)",
      },
      ["chapters/intro.md"] = {
        "# Introduction",
        "",
        "A paragraph with [next](second.md#repeat-1).",
        "",
        "## Reading",
        "",
        "More text.",
      },
      ["chapters/second.md"] = {
        "# Second",
        "",
        "## Repeat",
        "",
        "First occurrence.",
        "",
        "## Repeat",
        "",
        "Second occurrence.",
        "",
        "## 日本語 の見出し",
        "",
        "Final paragraph.",
      },
      ["chapters/last.md"] = { "# Last", "", "The final page." },
    }
    for path, lines in pairs(extra or {}) do
      files[path] = lines
    end
    for path, lines in pairs(files) do
      t.write(root .. "/" .. path, lines)
    end
    return root
  end
  local function with_book(opts, run)
    opts = opts or {}
    local original = {
      tab = vim.api.nvim_get_current_tabpage(),
      columns = vim.o.columns,
      lines = vim.o.lines,
      config = require("md-readable.config").get(),
      statusline = vim.o.statusline,
    }
    vim.o.columns, vim.o.lines = opts.columns or 120, 24
    vim.cmd("tabnew")
    local tab = vim.api.nvim_get_current_tabpage()
    local root = fixture(opts.files)
    local buf = vim.fn.bufadd(root .. "/" .. (opts.initial_path or "chapters/intro.md"))
    vim.fn.bufload(buf)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "markdown"
    vim.o.statusline = "end-to-end user statusline"
    api.setup({
      layout = opts.layout or "integrated",
      adapters = opts.adapters and opts.adapters(root) or {},
      images = { enabled = false },
      debounce = 0,
      navigation = { auto_open = opts.auto_open ~= false },
      minimap = { enable = false },
    })
    local session
    local ok, err = xpcall(function()
      local start = vim.uv.hrtime()
      session = Sessions.open(opts.mode or "current")
      local elapsed = (vim.uv.hrtime() - start) / 1e6
      run(session, root, buf, elapsed)
    end, debug.traceback)
    if session then
      Sessions.close(session)
    end
    for _, pending in ipairs(vim.tbl_values(Sessions.all())) do
      if
        pending.read_win
        and vim.api.nvim_win_is_valid(pending.read_win)
        and vim.api.nvim_win_get_tabpage(pending.read_win) == tab
      then
        Sessions.close(pending)
      end
    end
    if vim.api.nvim_tabpage_is_valid(tab) then
      vim.api.nvim_set_current_tabpage(tab)
      vim.cmd("tabclose!")
    end
    for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_is_valid(candidate) and vim.api.nvim_buf_get_name(candidate):sub(1, #root + 1) == root .. "/"
      then
        vim.api.nvim_buf_delete(candidate, { force = true })
      end
    end
    require("md-readable.config").setup(original.config)
    vim.o.columns, vim.o.lines, vim.o.statusline = original.columns, original.lines, original.statusline
    if vim.api.nvim_tabpage_is_valid(original.tab) then
      vim.api.nvim_set_current_tabpage(original.tab)
    end
    vim.wait(5)
    if not ok then
      error(err)
    end
  end
  local function source_cursor(session)
    local cursor = vim.api.nvim_win_get_cursor(session.read_win)
    return session.map:to_source(cursor[1] - 1, cursor[2])
  end
  local function displayed_heading(session, heading)
    local row, col = session.map:to_display(heading.range.start.row, 0)
    t.eq({ row + 1, col }, vim.api.nvim_win_get_cursor(session.read_win))
  end
  for _, mode in ipairs({ "current", "vert", "float" }) do
    t.test("real Session " .. mode .. ": mdBook next/previous preserves unsaved text and paired source", function()
      with_book({ mode = mode, columns = 180 }, function(s, root, original)
        t.eq("mdbook", s.snapshot.adapterId)
        t.eq("ok", s.nav_result.status)
        local original_lines = vim.api.nvim_buf_get_lines(original, 0, -1, false)
        vim.api.nvim_buf_set_lines(original, 2, 3, false, { "An unsaved change before chapter navigation." })
        s:refresh()
        t.eq(false, Navigation.move(s, "prev"))
        t.eq(true, Navigation.move(s, "next"))
        t.eq(root .. "/chapters/second.md", s.document.path)
        if mode ~= "current" then
          t.eq(s.source_buf, vim.api.nvim_win_get_buf(s.source_win))
        end
        t.eq(true, Navigation.move(s, "next"))
        t.eq(root .. "/chapters/last.md", s.document.path)
        t.eq(false, Navigation.move(s, "next"))
        t.eq(true, Navigation.move(s, "prev"))
        t.eq(true, Navigation.move(s, "prev"))
        t.eq(original, s.source_buf)
        t.ok(vim.bo[original].modified)
        t.eq("An unsaved change before chapter navigation.", s.document.lines[3])
        t.eq(original_lines, vim.fn.readfile(root .. "/chapters/intro.md"))
        t.eq("end-to-end user statusline", vim.o.statusline)
        local read_buf = s.read_buf
        Sessions.close(s)
        t.eq(false, vim.api.nvim_buf_is_valid(read_buf))
        t.ok(vim.api.nvim_buf_is_valid(original))
        if mode == "current" then
          t.eq(original, vim.api.nvim_win_get_buf(s.source_win))
        end
      end)
    end)
  end
  t.test("real vertical Session cursor events synchronize both directions using source map", function()
    with_book({ mode = "vert", auto_open = false }, function(s)
      local source_row, source_col = 4, 0
      vim.api.nvim_set_current_win(s.source_win)
      vim.api.nvim_win_set_cursor(s.source_win, { source_row + 1, source_col })
      vim.api.nvim_exec_autocmds("CursorMoved", {})
      local row, col = s.map:to_display(source_row, source_col)
      t.eq({ row + 1, col }, vim.api.nvim_win_get_cursor(s.read_win))
      local target_row, target_col = s.map:to_display(0, 0)
      vim.api.nvim_set_current_win(s.read_win)
      vim.api.nvim_win_set_cursor(s.read_win, { target_row + 1, target_col })
      vim.api.nvim_exec_autocmds("CursorMoved", {})
      local mapped_row, mapped_col = s.map:to_source(target_row, target_col)
      t.eq({ mapped_row + 1, mapped_col }, vim.api.nvim_win_get_cursor(s.source_win))
    end)
  end)
  t.test("real parsed duplicate/Unicode heading slugs resolve and navigate to mapped display positions", function()
    with_book({ mode = "vert", auto_open = false }, function(s, root)
      local linked = Resolver.resolve("second.md#repeat-1", { path = s.document.path, root_dir = root })
      t.eq("document", linked.type)
      t.eq(6, linked.row)
      s:navigate(linked.path, linked.anchor)
      t.eq("repeat", s.document.headings[2].id)
      t.eq("repeat-1", s.document.headings[3].id)
      displayed_heading(s, s.document.headings[3])
      t.eq(7, vim.api.nvim_win_get_cursor(s.source_win)[1])
      local unicode = s.document.headings[4]
      s:navigate(s.document.path, unicode.id)
      displayed_heading(s, unicode)
      local same =
        Resolver.resolve("#repeat", { path = s.document.path, root_dir = root, headings = s.document.headings })
      t.eq("document", same.type)
      t.eq(2, same.row)
      t.eq(
        "unresolved",
        Resolver.resolve("#not-a-heading", { path = s.document.path, root_dir = root, headings = s.document.headings }).type
      )
    end)
  end)
  for _, layout in ipairs({ "integrated", "separate", "ondemand" }) do
    t.test("real Session " .. layout .. " layout at 120/80/60 columns and explicit narrow navigation", function()
      with_book({ columns = 120, layout = layout }, function(s)
        local st = s._navigation
        if layout == "ondemand" then
          t.eq(nil, st.panels.book)
        else
          t.ok(st.panels.book)
          t.ok(vim.api.nvim_win_get_width(s.read_win) >= 48)
        end
        if layout == "separate" then
          t.ok(st.panels.outline)
        end
        vim.o.columns = 80
        vim.api.nvim_exec_autocmds("VimResized", {})
        vim.wait(100, function()
          return st.available_width == 80
        end, 5)
        t.eq(s.read_buf, vim.api.nvim_win_get_buf(s.read_win))
        t.eq(false, s.closed)
        if layout == "separate" then
          t.eq(nil, st.panels.outline)
        end
        vim.o.columns = 60
        vim.api.nvim_exec_autocmds("VimResized", {})
        t.ok(vim.wait(100, function()
          return st.panels.book == nil
        end, 5))
        Navigation.toggle(s)
        t.ok(st.panels.book)
        t.eq("editor", vim.api.nvim_win_get_config(st.panels.book.win).relative)
        t.eq(false, s.closed)
        t.ok(vim.api.nvim_buf_is_valid(s.source_buf))
        Navigation.close(s)
        t.eq("end-to-end user statusline", vim.o.statusline)
      end)
    end)
  end
  t.test("real Session duplicate path occurrences advance by selected occurrence and preserve tree model", function()
    with_book({
      adapters = function(root)
        return {
          root_dir = root,
          provider = function()
            return {
              schemaVersion = 1,
              rootDir = root,
              adapterId = "fixture",
              orderOrigin = "custom",
              diagnostics = {},
              trees = {
                {
                  id = "repeat",
                  title = "Repeated references",
                  items = {
                    {
                      id = "first-intro",
                      title = "First",
                      children = {},
                      target = { type = "document", path = "chapters/intro.md" },
                    },
                    {
                      id = "middle",
                      title = "Middle",
                      children = {},
                      target = { type = "document", path = "chapters/second.md" },
                    },
                    {
                      id = "last-intro",
                      title = "Last",
                      children = {},
                      target = { type = "document", path = "chapters/intro.md" },
                    },
                  },
                },
              },
            }
          end,
        }
      end,
    }, function(s, root)
      local tree = s.snapshot.trees[1]
      t.eq("first-intro", s._navigation.current.id)
      t.eq(true, Navigation.move(s, "next"))
      t.eq(true, Navigation.move(s, "next"))
      t.eq(root .. "/chapters/intro.md", s.document.path)
      t.eq("last-intro", s._navigation.current.id)
      t.eq(false, Navigation.move(s, "next"))
      t.eq(3, #tree.items)
      t.eq(0, #tree.items[1].children)
      t.eq(true, Navigation.move(s, "prev"))
      t.eq("middle", s._navigation.current.id)
    end)
  end)
  t.test("failed unsaved config reparse keeps stale navigation and recovery replaces snapshot", function()
    with_book({}, function(s, root)
      local old = s.snapshot
      local config = vim.fn.bufadd(root .. "/book.toml")
      vim.fn.bufload(config)
      vim.api.nvim_buf_set_lines(config, 0, -1, false, { "[book]", "src = arbitraryCall()" })
      s:load_navigation()
      s:refresh()
      t.eq("unsupported", s.nav_result.status)
      t.eq(old, s.snapshot)
      t.eq(true, s.stale)
      local panel = s._navigation.panels.book
      t.ok(table.concat(vim.api.nvim_buf_get_lines(panel.buf, 0, -1, false), "\n"):find("Stale", 1, true))
      vim.api.nvim_buf_set_lines(config, 0, -1, false, { "[book]", 'title = "Recovered"', 'src = "chapters"' })
      s:load_navigation()
      s:refresh()
      t.eq("ok", s.nav_result.status)
      t.eq(false, s.stale)
      t.ok(old ~= s.snapshot)
      t.eq("Recovered", s.snapshot.trees[1].title)
      t.eq(true, Navigation.move(s, "next"))
      t.eq(root .. "/chapters/second.md", s.document.path)
    end)
  end)
  t.test("1000-page mdBook actual Session initial load and reparse benchmark", function()
    local summary = { "# Summary" }
    local files = {}
    for i = 1, 1000 do
      local filename = string.format("page-%04d.md", i)
      summary[#summary + 1] = string.format("- [Page %04d](%s)", i, filename)
      files["chapters/" .. filename] = { "# Page " .. i, "", "Benchmark page." }
    end
    files["chapters/SUMMARY.md"] = summary
    with_book({ files = files, initial_path = "chapters/page-0001.md" }, function(s, root, _, initial)
      local clock = vim.uv or vim.loop
      local start = clock.hrtime()
      s:load_navigation()
      s:refresh()
      local reparse = (clock.hrtime() - start) / 1e6
      t.eq(1000, #s.snapshot.trees[1].items)
      local order = require("md-readable.navigation.order").reading_order(s.snapshot.trees[1], root)
      t.eq(1000, #order)
      t.eq("chapters/page-1000.md", order[1000].target.path)
      print(
        string.format(
          "BENCH navigation mdBook 1000 pages: initial Session.open %.2f ms; load_navigation+refresh %.2f ms (integrated UI enabled; fixture creation excluded)",
          initial,
          reparse
        )
      )
    end)
  end)
end
