return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local links = require("md-readable.ui.links")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  local long = "https://example.org/" .. string.rep("very-long-path-segment/", 10) .. "end"
  local function open()
    cleanup()
    api.setup({ navigation = { auto_open = false }, images = { enabled = false }, debounce = 0 })
    local dir = t.tempdir()
    t.write(dir .. "/next.md", { "# Next", "next paragraph" })
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, dir .. "/README.md")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "# Top",
      "",
      "Read [the guide](next.md) or [the site](" .. long .. ").",
      "Jump to [top](#top) or see ![diagram](d.png) and a note[^1].",
      "",
      "[^1]: Note.",
    })
    return api.open("vert"), dir
  end

  t.test("links panel lists kinds with tags and clipped targets", function()
    local s = open()
    local columns = vim.o.columns
    vim.o.columns = 100
    local win = links.open(s)
    t.eq(win, vim.api.nvim_get_current_win())
    t.eq("md-readable-links", vim.bo[vim.api.nvim_win_get_buf(win)].filetype)
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    t.eq("Links", lines[1])
    t.eq(6, #lines, "four links, footnote excluded")
    local width = vim.api.nvim_win_get_width(win)
    for row = 3, #lines do
      t.ok(vim.fn.strdisplaywidth(lines[row]) <= width, lines[row])
    end
    t.ok(lines[3]:match("^the guide  next%.md%s+%[doc%]$"), lines[3])
    t.ok(lines[4]:find("...", 1, true) and lines[4]:match("%[web%]$"), lines[4])
    t.ok(not lines[4]:find("end", 1, true), "long URL clipped")
    t.ok(lines[5]:match("%[anchor%]$"))
    t.ok(lines[6]:match("%[image%]$"))
    vim.cmd("normal q")
    t.ok(not vim.api.nvim_win_is_valid(win))
    t.eq(s.read_win, vim.api.nvim_get_current_win())
    vim.o.columns = columns
    cleanup()
  end)

  t.test("links panel opens a document with Enter and shows a link with o", function()
    local s, dir = open()
    local win = api.action("links") or s._links_panel.win
    vim.api.nvim_win_set_cursor(win, { 5, 0 })
    vim.cmd("normal o")
    t.ok(not vim.api.nvim_win_is_valid(win))
    local cursor = vim.api.nvim_win_get_cursor(s.read_win)
    t.eq({ 3, 9 }, { s.map:to_source(cursor[1] - 1, cursor[2]) }, "cursor on the link label")
    win = links.open(s)
    vim.api.nvim_win_set_cursor(win, { 3, 0 })
    vim.cmd('execute "normal \\<CR>"')
    t.eq(dir .. "/next.md", vim.api.nvim_buf_get_name(s.source_buf))
    t.eq(s.read_win, vim.api.nvim_get_current_win())
    win = links.open(s)
    sessions.close(s)
    t.ok(not vim.api.nvim_win_is_valid(win), "closing the session closes the list")
    cleanup()
  end)
end
