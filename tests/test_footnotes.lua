return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local source_map = require("md-readable.reader.source_map")
  local source = {
    "Footnote[^1] and [link](a.md)[^Note].",
    "",
    "[^1]: 脚注本文。",
    "[^note]: Named note with [docs](b.md)",
    "    continued line.",
    "",
    "[ref]: c.md",
  }
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end

  t.test("footnote definitions are parsed apart from link references", function()
    local doc = parse(source)
    local kinds = {}
    for _, link in ipairs(doc.links) do
      kinds[#kinds + 1] = link.kind .. ":" .. link.target
    end
    t.eq({ "footnote:^1", "document:a.md", "footnote:^Note", "document:b.md" }, kinds)
    t.eq(2, doc.footnotes["1"].row)
    t.eq(3, doc.footnotes["note"].row)
    t.eq(1, #doc.footnotes["note"].references)
    t.eq(nil, doc.references["1"])
    t.eq("c.md", doc.references["ref"].target)
    local types = {}
    for _, block in ipairs(doc.blocks) do
      types[#types + 1] = block.type
    end
    t.eq({ "paragraph", "blank", "footnote", "footnote", "blank", "reference" }, types)
    t.eq(0, #parse({ "Undefined[^x] stays text." }).links)
  end)

  t.test("footnote text is readable and copies its original Markdown", function()
    local value = render(parse(source), { width = 80 })
    t.eq("Footnote[1] and link[Note].", value.lines[1])
    t.eq("── Footnotes ", value.lines[3]:sub(1, #"── Footnotes "))
    t.eq("[1] 脚注本文。", value.lines[4])
    t.eq("[note] Named note with docs continued line.", value.lines[5])
    local map = source_map.new(source, value)
    local a = value.lines[1]:find("[1]", 1, true) - 1
    t.eq("[^1]", map:copy(0, a, 0, a + 1, "char"))
    t.eq("[^1]: 脚注本文。", map:copy(3, 0, 3, #value.lines[4], "char"))
    t.eq(nil, map:copy(2, 0, 2, #value.lines[3], "char"), "separator is decoration")
    t.eq("[^1]: 脚注本文。", map:copy(3, 0, 4, 0, "line"))
    t.eq(table.concat({ source[4], source[5] }, "\n"), map:copy(4, 0, 5, 0, "line"))
    local docs = value.lines[5]:find("docs", 1, true) - 1
    t.eq("[docs](b.md)", map:copy(4, docs, 4, docs + 4, "char"))
    local groups = {}
    for _, h in ipairs(value.highlights) do
      if h.row == 0 then
        groups[value.lines[1]:sub(h.start_col + 1, h.end_col)] = h.group
      end
    end
    t.eq("MdReadableFootnote", groups["[1]"])
  end)

  t.test("open jumps between a footnote reference and its definition", function()
    cleanup()
    api.setup({ navigation = { auto_open = false }, images = { enabled = false }, debounce = 0 })
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
    local s = api.open("current")
    s:jump_source(0, 9)
    api.action("open")
    local row = vim.api.nvim_win_get_cursor(s.read_win)[1] - 1
    t.eq(2, (s.map:to_source(row, 0)))
    vim.api.nvim_win_set_cursor(s.read_win, { row + 1, 1 })
    api.action("open")
    local back = vim.api.nvim_win_get_cursor(s.read_win)
    t.eq({ 0, 8 }, { s.map:to_source(back[1] - 1, back[2]) })
    cleanup()
  end)
end
