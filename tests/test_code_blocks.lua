return function(t)
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local code_theme = require("md-readable.ui.code_theme")
  local config = require("md-readable.config")
  local source = { "before", "", "```lua", 'local x = "s"', "```", "after" }
  local function draw(opts)
    return render(parse(source), vim.tbl_extend("force", { width = 30 }, opts or {}))
  end
  local function row_of(value, pattern)
    for index, line in ipairs(value.lines) do
      if line:find(pattern) then
        return index - 1, line
      end
    end
  end

  t.test("code blocks render as a full-width panel with the label in a chosen corner", function()
    local left = draw({ code = { label = "left" } })
    local block = left.code_blocks[1]
    t.eq(3, block.end_row - block.row, "label row, code row and bottom row")
    for row = block.row, block.end_row - 1 do
      t.eq(30, vim.fn.strdisplaywidth(left.lines[row + 1]), "row " .. row .. " spans the body width")
    end
    t.eq(" lua", (left.lines[block.row + 1]:gsub("%s+$", "")))
    t.eq(' local x = "s"', (left.lines[block.row + 2]:gsub("%s+$", "")), "one blank column before the code")
    t.eq("", vim.trim(left.lines[block.end_row]), "bottom padding row")
    local right = draw({ code = { label = "right" } })
    t.eq(string.rep(" ", 26) .. "lua ", right.lines[right.code_blocks[1].row + 1])
    -- The background is listed before the block's other highlights.
    local first
    for index, h in ipairs(left.highlights) do
      if h.row == block.row and not first then
        first = index
        t.eq("MdReadableCodeBlock", h.group)
        t.eq(0, h.start_col)
      end
    end
    t.ok(first)
  end)

  t.test("decoration keeps source mapping of the code text", function()
    local value = draw({ code = {} })
    local row = row_of(value, "local x")
    local found
    for _, segment in ipairs(value.segments) do
      if segment.row == row then
        found = segment
      end
    end
    t.ok(found, "code text has a segment")
    t.eq(3, found.source_row)
    t.eq(1, found.start_col, "after the blank column")
    t.eq(0, found.source_start)
  end)

  t.test("code.icons picks the icon provider; nil shows none", function()
    local saved = { package.loaded["mini.icons"], package.loaded["nvim-web-devicons"] }
    package.loaded["mini.icons"] = {
      get = function(category, name)
        if category == "filetype" and name == "lua" then
          return "M", "MiniIconsBlue", false
        end
        return "?", "MiniIconsGrey", true
      end,
    }
    package.loaded["nvim-web-devicons"] = {
      get_icon_by_filetype = function(filetype)
        if filetype == "lua" then
          return "D", "DevIconLua"
        end
      end,
      get_icon = function() end,
    }
    local function label(icons)
      local value = draw({ code = { label = "left", icons = icons } })
      return (value.lines[value.code_blocks[1].row + 1]:gsub("%s+$", ""))
    end
    t.eq(" M lua", label("mini"))
    t.eq(" D lua", label("web-devicons"))
    t.eq(" lua", label(nil))
    local value = draw({ code = { icons = "mini" } })
    local groups = {}
    for _, h in ipairs(value.highlights) do
      groups[h.group] = true
    end
    t.ok(groups.MiniIconsBlue, "icon keeps the provider's color")
    package.loaded["mini.icons"] = nil
    t.eq(" lua", label("mini"), "a provider that is not installed shows no icon")
    package.loaded["mini.icons"], package.loaded["nvim-web-devicons"] = saved[1], saved[2]
  end)

  t.test("presets color code blocks by role; plain colors keep the colorscheme", function()
    local names = vim.tbl_keys(code_theme.presets)
    table.sort(names)
    t.eq({
      "ayu-dark",
      "ayu-light",
      "catppuccin",
      "dracula",
      "github-dark",
      "github-light",
      "gruvbox-dark",
      "gruvbox-light",
      "tokyonight",
    }, names)
    for name, palette in pairs(code_theme.presets) do
      for _, role in ipairs(code_theme.roles) do
        t.ok(palette[role], name .. " defines " .. role)
      end
    end
    t.eq("keyword", code_theme.role("keyword.return"))
    t.eq("parameter", code_theme.role("variable.parameter"))
    t.eq("variable", code_theme.role("variable"))
    t.eq(nil, code_theme.role("spell"))
    local code = require("md-readable.renderers.code")
    local themed = code.highlights({ 'local x = "s"' }, "lua", { theme = "dracula", colors = {} })
    local groups = {}
    for _, h in ipairs(themed) do
      groups[h.group] = true
    end
    t.ok(groups.MdReadableCodeBlockKeyword, "local is a keyword")
    t.ok(groups.MdReadableCodeBlockString, "string literal")
    for group in pairs(groups) do
      t.ok(group:match("^MdReadableCodeBlock"), "only code block groups with a preset: " .. group)
    end
    local plain = code.highlights({ 'local x = "s"' }, "lua", { colors = {} })
    t.ok(plain[1].group:match("^@.*%.lua$"), "colorscheme captures without a palette")
    local partial = code.highlights({ 'local x = "s"' }, "lua", { colors = { keyword = "#ff0000" } })
    local mixed = {}
    for _, h in ipairs(partial) do
      mixed[h.group:match("^@") and "capture" or h.group] = true
    end
    t.ok(mixed.MdReadableCodeBlockKeyword and mixed.capture, "user colors replace only their roles")
  end)

  t.test("code block colors: gray-shifted background, preset and user overrides", function()
    local auto = code_theme.highlights({ colors = {} }, 0x1e1e2e)
    t.ok(auto.MdReadableCodeBlock.bg ~= 0x1e1e2e, "differs from the page")
    t.ok(auto.MdReadableCodeBlock.bg > 0x1e1e2e, "dark pages get a lighter block")
    t.ok(code_theme.highlights({ colors = {} }, 0xffffff).MdReadableCodeBlock.bg < 0xffffff, "light pages a darker one")
    local preset = code_theme.highlights({ theme = "github-dark", colors = {} }, 0)
    t.eq(0x24292e, preset.MdReadableCodeBlock.bg)
    t.eq(0xf97583, preset.MdReadableCodeBlockKeyword.fg)
    local custom = code_theme.highlights({ theme = "github-dark", colors = { bg = "#101010", keyword = "#00ff00" } }, 0)
    t.eq(0x101010, custom.MdReadableCodeBlock.bg)
    t.eq(0x00ff00, custom.MdReadableCodeBlockKeyword.fg)
    t.eq(0x9ecbff, custom.MdReadableCodeBlockString.fg, "other roles stay from the preset")
  end)

  t.test("reading windows get the session's code block colors", function()
    local theme = require("md-readable.ui.theme")
    theme.setup()
    local win = vim.api.nvim_get_current_win()
    local ns = assert(theme.apply(win, "default", { code = { theme = "tokyonight", colors = {}, label = "left" } }))
    t.eq(0x1a1b26, vim.api.nvim_get_hl(ns, { name = "MdReadableCodeBlock" }).bg)
    t.eq(0xbb9af7, vim.api.nvim_get_hl(ns, { name = "MdReadableCodeBlockKeyword" }).fg)
    theme.close(win)
  end)

  t.test("invalid code options are rejected", function()
    for _, case in ipairs({
      { { theme = "solarized" }, "code.theme must be one of" },
      { { label = "top" }, 'code.label must be "left" or "right"' },
      { { icons = true }, 'code.icons must be nil, "mini" or "web-devicons"' },
      { { colors = { keyword = "red" } }, 'code.colors.keyword must be "#rrggbb"' },
      { { colors = { unknown = "#ffffff" } }, "code.colors.unknown is not a known color" },
    }) do
      local ok, err = pcall(config.setup, { code = case[1] })
      t.ok(not ok and err:find(case[2], 1, true), tostring(err))
    end
    config.setup({})
  end)
end
