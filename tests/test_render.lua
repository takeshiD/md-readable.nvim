return function(t)
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local function draw(lines, opts) return render(parse(lines), opts or {}) end
  local function contains(lines, text) return table.concat(lines, "\n"):find(text, 1, true) ~= nil end
  t.test("basic Markdown display and semantic highlights", function()
    local value = draw({ "# Title", "", "**bold** *italic* ~~gone~~ `code`", "- [x] done", "> quoted", "", "Setext", "---" })
    t.eq("Title", value.lines[1]); t.ok(contains(value.lines, "bold italic gone code")); t.ok(contains(value.lines, "☑ done"))
    t.ok(contains(value.lines, "│ quoted")); t.eq("Setext", value.lines[#value.lines])
    local groups = {}; for _, h in ipairs(value.highlights) do groups[h.group] = true end
    t.ok(groups.MdReadableBold); t.ok(groups.MdReadableItalic); t.ok(groups.MdReadableStrike); t.ok(groups.MdReadableCode)
  end)
  t.test("links have full node and precise partial label coordinates", function()
    local source = "前 [導入手順](install.md) 後"
    local value = draw({ source })
    t.eq("前 導入手順 後", value.lines[1])
    local node; for _, s in ipairs(value.segments) do if s.kind == "node" then node = s end end
    t.ok(node); t.eq("導入手順", source:sub(node.source_start + 1, node.source_end))
    t.eq("[導入手順](install.md)", source:sub(node.full_start + 1, node.full_end))
  end)
  t.test("formatted link labels retain outer link node identity", function()
    local value = draw({ "[**bold** label](x.md)" })
    t.eq("bold label", value.lines[1])
    for _, segment in ipairs(value.segments) do t.eq("node", segment.kind); t.eq(0, segment.full_start); t.eq(22, segment.full_end) end
  end)
  t.test("entities display Unicode and preserve original entity byte span", function()
    local value = draw({ "A &amp; B &#x65E5;" })
    t.eq("A & B 日", value.lines[1]); t.eq(2, value.segments[2].source_start); t.eq(7, value.segments[2].source_end)
  end)
  t.test("wrapped nodes preserve fragment label ranges and original source identity", function()
    local source = "[abcdefghijk](target.md)"
    local value = draw({ source }, { width = 4 })
    t.eq({ "abcd", "efgh", "ijk" }, value.lines)
    t.eq({ 0, 0, 0 }, value.row_map)
    for i, segment in ipairs(value.segments) do
      t.eq(value.lines[i], source:sub(segment.source_start + 1, segment.source_end))
      t.eq(0, segment.full_start); t.eq(#source, segment.full_end)
    end
  end)
  t.test("wide and combining glyphs survive wrapping as graphemes", function()
    local value = draw({ "日é本語text" }, { width = 4 })
    t.eq("日é本語text", table.concat(value.lines))
    for _, line in ipairs(value.lines) do t.ok(vim.fn.strdisplaywidth(line) <= 4); t.ok(not line:match("^́")) end
  end)
  t.test("tabs expand into mapped display whitespace", function()
    local value = draw({ "a\tb" }, { width = 20, tabstop = 4 })
    t.eq("a   b", value.lines[1]); t.eq(1, value.segments[2].source_start); t.eq(2, value.segments[2].source_end)
  end)
  t.test("long URL omission retains host and full source range", function()
    local source = "https://example.org/" .. string.rep("long/", 20)
    local value = draw({ source }, { max_url_width = 30 })
    t.ok(value.lines[1]:find("https://example.org/", 1, true)); t.ok(value.lines[1]:find("…", 1, true))
    local omission = value.segments[#value.segments]; t.eq("omission", omission.kind); t.eq(#source, omission.full_end)
  end)
  t.test("short bare URLs render without recursively interpreting themselves", function()
    t.eq({ "https://example.org" }, draw({ "https://example.org" }).lines)
  end)
  t.test("tables align truncate retain full cell metadata and have unmapped borders", function()
    local value = draw({ "| Name | Value |", "| :--- | ---: |", "| 日é | very long cell content |" }, { width = 30, table = { max_cell_width = 8 } })
    t.ok(contains(value.lines, "…")); t.eq(4, #value.cells); t.eq("very long cell content", value.cells[4].text); t.ok(value.cells[4].omitted)
    for _, line in ipairs(value.lines) do t.ok(vim.fn.strdisplaywidth(line) <= 30) end
    for _, segment in ipairs(value.segments) do t.ok(segment.row ~= 1) end
    local omission; for _, segment in ipairs(value.segments) do if segment.kind == "omission" then omission = segment end end
    t.eq(value.cells[4].source_start, omission.full_start); t.eq(value.cells[4].source_end, omission.full_end)
  end)
  t.test("truncated link label pieces cannot claim whole-node selection", function()
    local value = draw({ "| Name |", "| --- |", "| [abcdefghijk](dest.md) |" }, { width = 20, table = { max_cell_width = 5 } })
    local nodes = {}
    for _, segment in ipairs(value.segments) do
      if segment.kind == "node" then nodes[#nodes + 1] = segment; t.eq(false, segment.node_complete) end
    end
    t.eq(1, #nodes); t.eq("abcd", value.lines[nodes[1].row + 1]:sub(nodes[1].start_col + 1, nodes[1].end_col))
  end)
  t.test("table clipping marks all fragments of a formatted partial label", function()
    local value = draw({ "| Name |", "| --- |", "| [**bold** and tail](dest.md) |" }, { width = 20, table = { max_cell_width = 7 } })
    local count = 0
    for _, segment in ipairs(value.segments) do
      if segment.kind == "node" then count = count + 1; t.eq(false, segment.node_complete) end
    end
    t.ok(count >= 2)
  end)
  t.test("fully retained links remain complete even when a later cell tail is omitted", function()
    local value = draw({ "| Name |", "| --- |", "| [ok](dest.md) long trailing text |" }, { width = 20, table = { max_cell_width = 6 } })
    local count = 0
    for _, segment in ipairs(value.segments) do
      if segment.kind == "node" then count = count + 1; t.ok(segment.node_complete ~= false) end
    end
    t.eq(1, count)
  end)
  t.test("URL omissions mark retained fragments incomplete before wrapping", function()
    local value = draw({ "https://example.org/long/long/long" }, { max_url_width = 24, width = 10 })
    local count = 0
    for _, segment in ipairs(value.segments) do
      if segment.kind == "node" then count = count + 1; t.eq(false, segment.node_complete) end
    end
    t.ok(count >= 2)
  end)
  t.test("narrow table fallback never loses columns", function()
    local value = draw({ "a | b | c | d", "--- | --- | --- | ---", "one | two | three | four" }, { width = 10 })
    t.eq(8, #value.cells); t.ok(contains(value.lines, "four"))
    for _, line in ipairs(value.lines) do t.ok(vim.fn.strdisplaywidth(line) <= 10) end
  end)
  t.test("escaped pipes and inline table code are rendered as text", function()
    local value = draw({ "a | b", "--- | ---", "日\\|本 | `a|b`" })
    t.ok(contains(value.lines, "日|本")); t.ok(contains(value.lines, "a|b"))
  end)
  t.test("missing code parser leaves complete code and its language descriptor", function()
    local value = draw({ "```imaginary_language", "  # untouched", "a < b", "```" })
    t.ok(contains(value.lines, "  # untouched")); t.ok(contains(value.lines, "a < b")); t.eq("imaginary_language", value.code_blocks[1].language)
  end)
  t.test("images and Mermaid provide source descriptors with safe fallback text", function()
    local value = draw({ "![architecture](arch.png)", "```mermaid", "graph TD; A-->B", "```" }, { image_height = 2 })
    t.eq(2, #value.images); t.eq("arch.png", value.images[1].path); t.eq("image", value.images[1].kind)
    t.eq("graph TD; A-->B", value.images[2].code); t.ok(contains(value.lines, "architecture")); t.ok(contains(value.lines, "graph TD"))
    for _, descriptor in ipairs(value.images) do t.eq("", value.lines[descriptor.row + 1]); t.eq(2, descriptor.height) end
    local plain = draw({ "![alt](x.png)" }, { media = { enabled = false } })
    t.eq(1, #plain.lines); t.eq(0, plain.images[1].height)
  end)
  t.test("details expand by zero based source row and preserve mappings", function()
    local lines = { "<details>", "<summary>More</summary>", "Hidden **content**", "</details>" }
    local closed = draw(lines); local opened = draw(lines, { expanded = { [0] = true } })
    t.ok(not contains(closed.lines, "Hidden")); t.ok(contains(opened.lines, "Hidden content"))
    t.eq(2, opened.row_map[2]); t.eq("details", closed.controls[1].kind)
  end)
  t.test("static tabs switch without executing components", function()
    local lines = { "<Tabs>", '<Tab value="one" label="One">', "first", "</Tab>", '<Tab value="two" label="Two">', "second", "</Tab>", "</Tabs>" }
    local value = draw(lines, { tabs = { [0] = 2 } })
    t.ok(contains(value.lines, "[Two]")); t.ok(contains(value.lines, "second")); t.ok(not contains(value.lines, "first")); t.eq(5, value.row_map[2])
  end)
  t.test("MkDocs dedentation preserves source mapping", function()
    local lines = { '=== "One"', "    [label](x.md)", '=== "Two"', "    other" }
    local value = draw(lines)
    t.eq("label", value.lines[2]); t.eq(1, value.segments[1].source_row); t.eq(5, value.segments[1].source_start); t.eq(4, value.segments[1].full_start)
  end)
  t.test("callout content and unknown HTML remain readable", function()
    local value = draw({ "> [!NOTE] Remember", "> text **bold**", "", "<Custom unsafe={run()} />" })
    t.ok(contains(value.lines, "Remember")); t.ok(contains(value.lines, "text bold")); t.ok(contains(value.lines, "<Custom unsafe={run()} />"))
  end)
  t.test("empty document renders safely without changing input", function()
    t.eq({ "" }, draw({}).lines)
    local lines = { "# Title", "text" }; local document = parse(lines); draw(lines, { width = 80 }); render(document, { width = 120 })
    t.eq({ "# Title", "text" }, document.lines); t.eq(lines, document.lines)
  end)
  t.test("ordinary soft lines join while retaining all source rows and byte spans", function()
    local source = { "This is", "one **paragraph** with", "[a link](x.md)." }
    local value = draw(source)
    t.eq({ "This is one paragraph with a link." }, value.lines)
    t.eq({ { 0, 1, 2 } }, value.source_rows); t.eq({ 0 }, value.row_map)
    for _, segment in ipairs(value.segments) do
      t.eq(source[segment.source_row + 1]:sub(segment.source_start + 1, segment.source_end),
        value.lines[segment.row + 1]:sub(segment.start_col + 1, segment.end_col))
    end
  end)
  t.test("CJK soft breaks join without artificial spaces and wrap with source identity", function()
    local source = { "日本語の", "文章です", "終わり" }
    local value = draw(source, { width = 12 })
    t.eq("日本語の文章です終わり", table.concat(value.lines))
    t.eq({ 0, 1 }, value.source_rows[1]); t.eq({ 1, 2 }, value.source_rows[2])
    for _, segment in ipairs(value.segments) do
      t.eq(source[segment.source_row + 1]:sub(segment.source_start + 1, segment.source_end),
        value.lines[segment.row + 1]:sub(segment.start_col + 1, segment.end_col))
    end
  end)
  t.test("explicit Markdown hard breaks preserve separate lines without source markers", function()
    local value = draw({ "line one  ", "line two\\", "line three", "continued", "", "New paragraph" })
    t.eq({ "line one", "line two", "line three continued", "", "New paragraph" }, value.lines)
    t.eq({ { 0 }, { 1 }, { 2, 3 }, { 4 }, { 5 } }, value.source_rows)
  end)
  t.test("unknown HTML and image source lines never join surrounding paragraphs", function()
    local value = draw({ "before", "<Widget value={1} />", "after", "![alt](x.png)", "last" }, { media = { enabled = false } })
    t.eq({ "before", "<Widget value={1} />", "after", "[Image: alt]", "last" }, value.lines)
  end)
  t.test("joined paragraphs within dedented tabs preserve original source columns", function()
    local source = { '=== "Tab"', "    first", "    [second](x.md)", "    third" }
    local value = draw(source)
    t.eq("first second third", value.lines[2]); t.eq({ 1, 2, 3 }, value.source_rows[2])
    for _, segment in ipairs(value.segments) do
      t.eq(source[segment.source_row + 1]:sub(segment.source_start + 1, segment.source_end),
        value.lines[segment.row + 1]:sub(segment.start_col + 1, segment.end_col))
    end
  end)
  local has_map, source_map = pcall(require, "md-readable.reader.source_map")
  if has_map then
    t.test("real SourceMap distinguishes truncated link text and its cell ellipsis", function()
      local source = { "| Name |", "| --- |", "| [abcdefghijk](dest.md) |" }
      local value = draw(source, { width = 20, table = { max_cell_width = 5 } })
      local map = source_map.new(source, value)
      for _, segment in ipairs(value.segments) do
        if segment.source_row == 2 and segment.kind == "node" then
          t.eq("abcd", map:copy(segment.row, segment.start_col, segment.row, segment.end_col, "char"))
        elseif segment.source_row == 2 and segment.kind == "omission" then
          t.eq("[abcdefghijk](dest.md)", map:copy(segment.row, segment.start_col, segment.row, segment.end_col, "char"))
        end
      end
    end)
    t.test("real SourceMap copies all joined source lines and locates their individual text", function()
      local source = { "first source line", "second source line" }
      local value = draw(source)
      local map = source_map.new(source, value)
      t.eq(table.concat(source, "\n"), map:copy(0, 0, 0, #value.lines[1], "line"))
      local row, col = map:to_display(1, 0)
      t.eq(0, row); t.eq(18, col)
      local original_row, original_col = map:to_source(row, col)
      t.eq(1, original_row); t.eq(0, original_col)
    end)
  end
end
