return function(t)
  local function map()
    local source = { "[導入手順](installation.md)", "| abcdefghij |", "wrapped words" }
    return require("md-readable.reader.source_map").new(source, {
      lines = { "導入手順", "abc…", "wrapped", "words", "────" },
      row_map = { 0, 1, 2, 2 },
      segments = {
        {
          row = 0,
          start_col = 0,
          end_col = 12,
          source_row = 0,
          source_start = 1,
          source_end = 13,
          kind = "node",
          full_start = 0,
          full_end = #source[1],
        },
        { row = 1, start_col = 0, end_col = 3, source_row = 1, source_start = 2, source_end = 5, kind = "text" },
        {
          row = 1,
          start_col = 3,
          end_col = 6,
          source_row = 1,
          source_start = 5,
          source_end = 12,
          kind = "omission",
          full_start = 2,
          full_end = 12,
        },
        { row = 2, start_col = 0, end_col = 7, source_row = 2, source_start = 0, source_end = 7, kind = "text" },
        { row = 3, start_col = 0, end_col = 5, source_row = 2, source_start = 8, source_end = 13, kind = "text" },
      },
    })
  end
  t.test("source copy preserves complete links but respects a partial Japanese label", function()
    t.eq("導入", map():copy(0, 0, 0, 6, "char"))
    t.eq("[導入手順](installation.md)", map():copy(0, 0, 0, 12, "char"))
  end)
  t.test("omitted cell copies original and decoration does not overwrite a register", function()
    t.eq("abcdefghij", map():copy(1, 0, 1, 6, "char"))
    t.eq("abc", map():copy(1, 0, 1, 3, "char"))
    t.eq(nil, map():copy(4, 0, 4, 12, "char"))
  end)
  t.test("wrapped source lines deduplicate on linewise yank", function()
    local text, kind = map():copy(2, 0, 4, 0, "line")
    t.eq("wrapped words", text)
    t.eq("V", kind)
    local row, col = map():to_display(2, 9)
    t.eq(3, row)
    t.eq(1, col)
    row, col = map():to_source(3, 1)
    t.eq(2, row)
    t.eq(9, col)
  end)
  t.test("wrapped links only expand when every fragment is selected", function()
    local original = "[abcdef](x)"
    local rendered = {
      lines = { "abc", "def" },
      row_map = { 0, 0 },
      segments = {
        {
          row = 0,
          start_col = 0,
          end_col = 3,
          source_row = 0,
          source_start = 1,
          source_end = 4,
          kind = "node",
          full_start = 0,
          full_end = #original,
        },
        {
          row = 1,
          start_col = 0,
          end_col = 3,
          source_row = 0,
          source_start = 4,
          source_end = 7,
          kind = "node",
          full_start = 0,
          full_end = #original,
        },
      },
    }
    local m = require("md-readable.reader.source_map").new({ original }, rendered)
    t.eq("abc", m:copy(0, 0, 0, 3, "char"))
    t.eq(original, m:copy(0, 0, 1, 3, "char"))
    local row, col = m:to_display(0, 5)
    t.eq(1, row)
    t.eq(1, col)
    rendered.segments[1].node_complete = false
    t.eq("abcdef", m:copy(0, 0, 1, 3, "char"))
  end)
  t.test("linewise joined prose retains every source line, decoration retains none", function()
    local m = require("md-readable.reader.source_map").new(
      { "one", "two" },
      {
        lines = { "one two", "──" },
        row_map = { 0, 1 },
        source_rows = { { 0, 1 }, {} },
        segments = {
          { row = 0, start_col = 0, end_col = 3, source_row = 0, source_start = 0, source_end = 3, kind = "text" },
          { row = 0, start_col = 4, end_col = 7, source_row = 1, source_start = 0, source_end = 3, kind = "text" },
        },
      }
    )
    t.eq("one\ntwo", m:copy(0, 0, 1, 0, "line"))
    t.eq(nil, m:copy(1, 0, 2, 0, "line"))
  end)
end
