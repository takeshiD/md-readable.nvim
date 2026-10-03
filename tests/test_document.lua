return function(t)
  local parse = require("md-readable.document.parser").parse
  local tables = require("md-readable.document.table")
  t.test("headings exclude frontmatter and fenced code; duplicate slugs and skipped levels", function()
    local doc = parse({ "---", "title: Test", "---", "# 日本語", "### Child", "body", "# 日本語", "```md", "# invisible", "```", "Setext", "===" })
    t.eq(4, #doc.headings); t.eq("日本語", doc.headings[1].id); t.eq("日本語-1", doc.headings[3].id)
    t.eq("日本語", doc.headings[2].parent); t.eq(6, doc.headings[1].sectionRange["end"].row)
    t.eq(10, doc.headings[4].range.start.row); t.eq(12, doc.headings[4].range["end"].row)
  end)
  t.test("ATX closing hashes require whitespace", function()
    local doc = parse({ "# abc#", "# abc #", "####### not heading", "#" })
    t.eq("abc#", doc.headings[1].title); t.eq("abc", doc.headings[2].title); t.eq(3, #doc.headings)
  end)
  t.test("link source byte ranges preserve Japanese and nested destinations", function()
    local line = "前 [導入手順](docs/a(b).md#章) 後"
    local link = parse({ line }).links[1]
    t.eq("導入手順", link.text); t.eq("docs/a(b).md#章", link.target)
    t.eq("[導入手順](docs/a(b).md#章)", line:sub(link.range.start.byteColumn + 1, link.range["end"].byteColumn))
    t.eq("導入手順", line:sub(link.label_start + 1, link.label_end))
  end)
  t.test("reference links preserve style and resolve case-insensitively", function()
    local doc = parse({ "[Read][Guide] [Guide][] [Guide] [missing][nope]", "[guide]: ./intro.md" })
    t.eq(4, #doc.links); t.eq("./intro.md", doc.links[1].target); t.eq("reference", doc.links[3].style)
    t.eq("unresolved", doc.links[4].kind)
  end)
  t.test("escaped links and inline code never become links", function()
    local doc = parse({ "`[fake](x)` \\[escaped](x) [real](#top)", "```", "[fake](x)", "```" })
    t.eq(1, #doc.links); t.eq("anchor", doc.links[1].kind)
  end)
  t.test("autolinks, bare URLs and images classify without network", function()
    local doc = parse({ "<https://example.org/a> https://example.org/b. ![alt](pic.png) [file](a.pdf)" })
    t.eq(4, #doc.links); t.eq("https://example.org/b", doc.links[2].target)
    t.eq("image", doc.links[3].kind); t.eq("asset", doc.links[4].kind)
  end)
  t.test("tables share escaped pipe code span byte ranges and alignment", function()
    local lines = { "| 名称 | `a|b` | note |", "| :--- | ---: | :---: |", "| 日\\|本 | é | 長文 |" }
    local value = tables.parse(lines, 0)
    t.eq({ "left", "right", "center" }, value.alignments); t.eq(3, value.end_row)
    t.eq("`a|b`", value.rows[1].cells[2].text); t.eq("日\\|本", value.rows[2].cells[1].text)
    for _, row in ipairs(value.rows) do for _, cell in ipairs(row.cells) do t.eq(cell.text, lines[row.source_row + 1]:sub(cell.start_col + 1, cell.end_col)) end end
  end)
  t.test("tables without outside pipes and missing cells", function()
    local value = tables.parse({ "a | b", "--- | ---", "v |" }, 0)
    t.eq(2, #value.rows[2].cells); t.eq("", value.rows[2].cells[2].text)
    t.eq(nil, tables.parse({ "a | b", "--x | --" }, 0))
  end)
  t.test("static extension families and ranges", function()
    local doc = parse({ "> [!NOTE] Remember", "> text", "", ":::warning Title", "Body", ":::", "", '!!! tip "Tip"', "    body", "", "<details>", "<summary>More</summary>", "Hidden", "</details>" })
    t.eq("callout", doc.blocks[1].type); t.eq("Remember", doc.blocks[1].title)
    t.eq("callout", doc.blocks[3].type); t.eq("Title", doc.blocks[3].title)
    t.eq("Tip", doc.blocks[5].title); t.eq("details", doc.blocks[6].type)
  end)
  t.test("static MDX and MkDocs tab collections", function()
    local doc = parse({ "<Tabs>", '<TabItem value="a" label="Alpha">', "one", "</TabItem>", '<Tab value="b" label="Beta">', "two", "</Tab>", "</Tabs>", "", '=== "One"', "    text", '=== "Two"', "    more" })
    t.eq("tabs", doc.blocks[1].type); t.eq(2, #doc.blocks[1].tabs); t.eq("Beta", doc.blocks[1].tabs[2].title)
    t.eq("tabs", doc.blocks[3].type); t.eq(2, #doc.blocks[3].tabs)
  end)
  t.test("unknown dynamic components remain literal paragraphs", function()
    local doc = parse({ "<Tabs>", "<Tab label={runCode()}>", "text", "</Tab>", "</Tabs>", "<Custom arbitrary={1} />" })
    t.eq("paragraph", doc.blocks[1].type); t.eq("paragraph", doc.blocks[6].type)
  end)
  t.test("input remains immutable and metadata is retained", function()
    local lines = { "# Original" }; local doc = parse(lines, { bufnr = 7, changedtick = 9, path = "/doc.md" })
    lines[1] = "edited"; t.eq("# Original", doc.lines[1]); t.eq(9, doc.changedtick); t.eq(7, doc.bufnr)
  end)
  t.test("hidden extension headings remain navigable and nested code links are excluded", function()
    local doc = parse({ "<details>", "<summary>More</summary>", "# Hidden", "```", "[fake](x)", "```", "</details>", "", '=== "Tab"', "    ## Inside", "    ```", "    [bad](x)", "    ```" })
    t.eq(2, #doc.headings); t.eq("Hidden", doc.headings[1].title); t.eq("Inside", doc.headings[2].title); t.eq(0, #doc.links)
  end)
  t.test("definitions inside fences cannot resolve references", function()
    local doc = parse({ "[real][ref]", "```", "[ref]: example.md", "```" })
    t.eq("unresolved", doc.links[1].kind)
  end)
  t.test("direct table parsing retains indentation and original cell byte columns", function()
    local lines = { "  | A | B |", "  |---|---|", "  | x | y |" }
    local value = tables.parse(lines, 0)
    t.eq("  ", value.prefix)
    for _, row in ipairs(value.rows) do for _, cell in ipairs(row.cells) do
      t.eq(cell.text, lines[row.source_row + 1]:sub(cell.start_col + 1, cell.end_col))
    end end
  end)
  t.test("quoted tables preserve container prefix and stop before leaving their quote", function()
    local lines = { "> > | A | B |", "> > |---|---|", "> > |x|y|", "|outside|quote|" }
    local value = tables.parse(lines, 0)
    t.eq("> > ", value.prefix); t.eq(3, value.end_row); t.eq(2, #value.rows)
    for _, row in ipairs(value.rows) do for _, cell in ipairs(row.cells) do
      t.eq(cell.text, lines[row.source_row + 1]:sub(cell.start_col + 1, cell.end_col))
    end end
    t.eq("> > ", parse(lines).tables[1].prefix)
  end)
  t.test("callout tables restore the quote removed for recursive parsing", function()
    local lines = { "> [!NOTE]", "> | A | B |", "> |---|---|", "> |x|y|" }
    local value = parse(lines).tables[1]
    t.eq("> ", value.prefix); t.eq(1, value.start_row); t.eq(4, value.end_row)
    for _, row in ipairs(value.rows) do for _, cell in ipairs(row.cells) do
      t.eq(cell.text, lines[row.source_row + 1]:sub(cell.start_col + 1, cell.end_col))
    end end
  end)
  t.test("nested dedentation and quoting compose the original table prefix once", function()
    local lines = { '!!! note "Outer"', "    > [!NOTE] Inner", "    >   | A | B |", "    >   |---|---|", "    >   |x|y|" }
    local value = parse(lines).tables[1]
    t.eq("    >   ", value.prefix); t.eq(2, value.start_row)
    for _, row in ipairs(value.rows) do for _, cell in ipairs(row.cells) do
      t.eq(cell.text, lines[row.source_row + 1]:sub(cell.start_col + 1, cell.end_col))
    end end
  end)
  local has_format, formatter = pcall(require, "md-readable.table.format")
  if has_format then
    t.test("real format and edit preserve the surrounding callout and its cell values", function()
      local source = { "> [!NOTE]", "> | A | B |", "> |---|---|", "> |x|y|" }
      local value = parse(source).tables[1]
      local formatted = formatter.format(value)
      for _, line in ipairs(formatted) do t.eq("> ", line:sub(1, 2)) end
      local updated = { source[1] }; vim.list_extend(updated, formatted)
      local reparsed = parse(updated)
      t.eq("callout", reparsed.blocks[1].type); t.eq("> ", reparsed.tables[1].prefix)
      t.eq("x", reparsed.tables[1].rows[2].cells[1].text)
      local edited = require("md-readable.table.edit").edit(reparsed.tables[1], "col_after", 1, 1)
      for _, line in ipairs(edited) do t.eq("> ", line:sub(1, 2)) end
      t.eq(3, #tables.parse(edited, 0).alignments)
    end)
  end
end
