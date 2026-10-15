return function(t)
  local alerts = require("md-readable.ui.alerts")
  local config = require("md-readable.config")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  ---@param lines string[]
  ---@param user? MdReadableUserConfigAlerts
  local function draw(lines, user)
    local opts = vim.tbl_deep_extend("force", vim.deepcopy(alerts.defaults), user or {})
    return render(parse(lines), { alerts = opts })
  end
  ---@return string? group Highlight group covering display row `row` at column 0
  local function group_at(value, row)
    for _, h in ipairs(value.highlights) do
      if h.row == row and h.start_col == 0 then
        return h.group
      end
    end
  end

  t.test("GitHub alerts get the kind's icon, title and color group", function()
    local value = draw({ "> [!NOTE]", "> Body", "", "> [!WARNING] Mind the gap" }, { icons = "unicode" })
    t.eq("ⓘ Note", value.lines[1])
    t.eq("MdReadableAlertNote", group_at(value, 0))
    t.ok(vim.tbl_contains(value.lines, "⚠ Mind the gap"), "an explicit title is kept")
    local nerd = draw({ "> [!CAUTION]" }, { icons = "nerd" })
    t.eq(alerts.icon_sets.nerd.caution .. " Caution", nerd.lines[1])
  end)

  t.test("admonition names map to the closest kind; unknown kinds keep the plain marker", function()
    local value = draw(
      { "!!! danger", "    Body", "", ":::info", "Text", ":::", "", "> [!CUSTOM]" },
      { icons = "unicode" }
    )
    t.eq("⊘ Caution", value.lines[1])
    t.eq("MdReadableAlertCaution", group_at(value, 0))
    t.ok(vim.tbl_contains(value.lines, "ⓘ Note"), table.concat(value.lines, "\n"))
    t.ok(vim.tbl_contains(value.lines, "▌ CUSTOM"), "an unknown kind")
  end)

  t.test("icons, titles and colors are configurable per kind", function()
    local value = draw({ "> [!TIP]", "", "> [!NOTE]" }, {
      kinds = { tip = { icon = "*", title = "Hint" }, note = { icon = false } },
    })
    t.eq("* Hint", value.lines[1])
    t.ok(vim.tbl_contains(value.lines, "▌ Note"), "icon = false keeps the marker")
    local plain = draw({ "> [!TIP]" }, { icons = false })
    t.eq("▌ Tip", plain.lines[1])
    local off = draw({ "> [!TIP]" }, { enable = false })
    t.eq("▌ TIP", off.lines[1])
    t.eq("MdReadableCallout", group_at(off, 0))

    local custom = draw({ "> [!TODO]" }, { kinds = { todo = { icon = "+", title = "To do", color = "#123456" } } })
    t.eq("+ To do", custom.lines[1], "a configured kind wins over its alias")
    t.eq("MdReadableAlertTodo", group_at(custom, 0))
  end)

  t.test("default colors follow GitHub for the background; explicit colors win", function()
    local dark = alerts.highlights(alerts.defaults, "dark")
    t.eq({ fg = 0x4493f8, bold = true }, dark.MdReadableAlertNote)
    t.eq({ fg = 0xd1242f, bold = true }, alerts.highlights(alerts.defaults, "light").MdReadableAlertCaution)
    local opts = vim.deepcopy(alerts.defaults)
    opts.kinds.note.color = "DiagnosticInfo"
    opts.kinds.tip.color = "#010203"
    local custom = alerts.highlights(opts, "dark")
    t.eq({ link = "DiagnosticInfo" }, custom.MdReadableAlertNote)
    t.eq({ fg = 0x010203, bold = true }, custom.MdReadableAlertTip)
  end)

  t.test("setup validates alert options", function()
    local saved = config.options
    for _, bad in ipairs({
      { icons = "emoji" },
      { kinds = { note = { icon = 1 } } },
      { kinds = { note = { color = true } } },
      { kinds = { note = "x" } },
    }) do
      local ok = pcall(config.setup, { alerts = bad })
      t.ok(not ok, vim.inspect(bad))
    end
    t.ok(pcall(config.setup, { alerts = { icons = "nerd", kinds = { note = { color = "#000000" } } } }))
    config.options = saved
  end)
end
