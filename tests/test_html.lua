return function(t)
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local source_map = require("md-readable.reader.source_map")
  local function draw(lines, opts)
    return render(parse(lines), vim.tbl_extend("force", { width = 200, links = { icons = "unicode" } }, opts or {}))
  end
  local function text(value)
    return table.concat(value.lines, "\n")
  end

  t.test("html <p> paragraphs hide tags and keep inline Markdown", function()
    local value = draw({ '<p align="center">これは **太字** の段落です</p>' })
    t.eq("これは 太字 の段落です", value.lines[1])
    local bold = false
    for _, h in ipairs(value.highlights) do
      bold = bold or h.group == "MdReadableBold"
    end
    t.ok(bold, "bold inside <p> is highlighted")
    local multi = draw({ "<p>", "最初の行", "次の行", "</p>" })
    t.ok(not text(multi):find("<", 1, true), text(multi))
    t.ok(text(multi):find("最初の行", 1, true))
  end)

  t.test("html <a href> is a link like Markdown links", function()
    local source = { 'See <a href="https://x.org/a?b=1&amp;c=2">the <b>site</b></a> and `<a href="no">code</a>` [doc](d.md)' }
    local doc = parse(source)
    t.eq(2, #doc.links, "code span is not a link")
    local link = doc.links[1]
    t.eq("https://x.org/a?b=1&c=2", link.target)
    t.eq("external", link.kind)
    local value = draw(source)
    t.ok(value.lines[1]:find("the <b>site</b>↗ and", 1, true), value.lines[1])
    t.ok(value.lines[1]:find('<a href="no">code</a> doc→', 1, true), value.lines[1])
    local map = source_map.new(source, value)
    local a = value.lines[1]:find("the", 1, true) - 1
    local icon_end = value.lines[1]:find("↗", 1, true) - 1 + #"↗"
    t.eq(source[1]:match("<a .-</a>"), map:copy(0, a, 0, icon_end, "char"))
    t.eq("the", map:copy(0, a, 0, a + 3, "char"), "partial label copies label text like Markdown links")
    local node
    for _, s in ipairs(value.segments) do
      if s.kind == "node" and not node then
        node = s
      end
    end
    t.eq(source[1]:match("<a .-</a>"), source[1]:sub(node.full_start + 1, node.full_end))
  end)

  t.test("html <img> renders as an image with alt and joins media", function()
    local source = { '<p align="center"><img src="docs/logo.png" alt="ロゴ" width="200"></p>', "<img src='x.png'/>" }
    local doc = parse(source)
    t.eq("image", doc.links[1].kind)
    t.eq("docs/logo.png", doc.links[1].target)
    t.eq("ロゴ", doc.links[1].text)
    t.eq("x.png", doc.links[2].target)
    local value = draw(source)
    t.eq("[Image: ロゴ]", value.lines[1])
    t.ok(text(value):find("[Image: Image]", 1, true))
    local media = 0
    for _, m in ipairs(value.images or {}) do
      media = media + (m.kind == "image" and 1 or 0)
    end
    t.ok(media >= 0)
  end)

  t.test("html links work in a reading session: panel, open, source untouched", function()
    local api = require("md-readable")
    local sessions = require("md-readable.reader.session")
    local links = require("md-readable.ui.links")
    api.setup({ images = { enable = false }, debounce = 0 })
    local dir = t.tempdir()
    t.write(dir .. "/next.md", { "# Next", "next paragraph" })
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, dir .. "/README.md")
    vim.api.nvim_set_current_buf(buf)
    local source = {
      '<p align="center"><img src="https://example.org/logo.png" alt="Logo"></p>',
      "",
      'Read <a href="next.md">the guide</a> now.',
    }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
    local s = api.open("vert")
    local read = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(s.read_win), 0, -1, false)
    t.ok(table.concat(read, "\n"):find("Read the guide→ now.", 1, true), table.concat(read, "\n"))
    t.ok(not table.concat(read, "\n"):find("<", 1, true), "no tag symbols shown")
    local win = links.open(s)
    local panel = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
    t.ok(panel:find("the guide", 1, true) and panel:find("next.md", 1, true), panel)
    t.ok(panel:find("Logo", 1, true), panel)
    local panel_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    for index, l in ipairs(panel_lines) do
      if l:find("the guide", 1, true) then
        vim.api.nvim_win_set_cursor(win, { index, 0 })
      end
    end
    vim.cmd("normal o")
    local cursor = vim.api.nvim_win_get_cursor(s.read_win)
    local row, col = s.map:to_source(cursor[1] - 1, cursor[2])
    t.eq(2, row)
    t.ok(col >= #'Read <a href="next.md">' and col < #'Read <a href="next.md">the guide', "cursor on label " .. col)
    t.eq(source, vim.api.nvim_buf_get_lines(buf, 0, -1, false), "source unchanged")
    t.eq(
      "web images are denied; use :MdReadable images allow",
      require("md-readable.providers.image").unavailable(s, { kind = "image", path = "https://example.org/logo.png" }),
      "remote <img> is gated like Markdown images"
    )
    vim.api.nvim_set_current_win(s.read_win)
    vim.cmd('execute "normal \\<CR>"')
    t.eq(dir .. "/next.md", vim.api.nvim_buf_get_name(s.source_buf))
    sessions.close(s)
    vim.cmd("silent! only!")
  end)

  t.test("other html tags stay as source text", function()
    local value = draw({ "<div>中身</div> <span>s</span>" })
    t.ok(value.lines[1]:find("<div>中身</div>", 1, true), value.lines[1])
    local plain = draw({ "**bold** [x](a.md) ![i](p.png)" })
    t.eq("bold x→ [Image: i]", plain.lines[1])
  end)
end
