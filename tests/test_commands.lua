return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  vim.cmd("runtime plugin/md-readable.lua")
  local function capture(fn)
    local messages, notify = {}, vim.notify
    vim.notify = function(message, level)
      messages[#messages + 1] = { message = message, level = level }
    end
    local ok, err = pcall(fn)
    vim.notify = notify
    assert(ok, err)
    return messages
  end
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  t.test("command errors show only the user-facing message", function()
    cleanup()
    api.setup({ navigation = { auto_open = false }, images = { enabled = false }, debounce = 0 })
    local cases = {
      { "foo", "md-readable: Unknown MdReadable command: foo" },
      { "nav", "md-readable: Open a reading view with :MdReadable first" },
      { "focus maybe", "md-readable: focus: expected on | off | toggle, got maybe" },
      { "images", "md-readable: images: expected allow | deny" },
      { "table format x", "md-readable: table: count must be a number, got x" },
    }
    for _, case in ipairs(cases) do
      local messages = capture(function()
        vim.cmd("MdReadable " .. case[1])
      end)
      t.eq(1, #messages, case[1])
      t.eq(case[2], messages[1].message)
      t.eq(vim.log.levels.ERROR, messages[1].level)
      t.ok(not messages[1].message:find("%.lua:%d+"), "no file position in " .. messages[1].message)
    end
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Title", "text" })
    api.open("current")
    local messages = capture(function()
      vim.cmd("MdReadable theme sepia")
      vim.cmd("MdReadable table")
    end)
    t.eq("md-readable: theme: expected default | dark | light, got sepia", messages[1].message)
    t.eq("md-readable: Cursor is not in a Markdown table", messages[2].message)
    cleanup()
  end)
  t.test("internal errors keep their traceback in message history", function()
    local echoed, echo = {}, vim.api.nvim_echo
    vim.api.nvim_echo = function(chunks, history)
      echoed[#echoed + 1] = { text = chunks[1][1], history = history }
    end
    local messages = capture(function()
      require("md-readable.errors").report(function()
        error("boom")
      end)
    end)
    vim.api.nvim_echo = echo
    t.ok(messages[1].message:find("internal error", 1, true))
    t.ok(echoed[1].history)
    t.ok(echoed[1].text:find("stack traceback", 1, true))
  end)
  t.test("completion covers subcommand arguments by position", function()
    local function complete(line)
      local lead = line:match("(%S*)$")
      return api.complete(lead, line, #line)
    end
    t.ok(vim.tbl_contains(complete("MdReadable "), "focus"))
    t.eq({ "theme", "table", "tab" }, complete("MdReadable t"))
    t.eq({ "on", "off", "toggle" }, complete("MdReadable focus "))
    t.eq({ "off" }, complete("MdReadable focus of"))
    t.eq({ "default", "dark", "light" }, complete("MdReadable theme "))
    t.eq({ "on", "off", "toggle", "focus" }, complete("MdReadable minimap "))
    t.eq({ "row-before", "row-after", "row-delete" }, complete("MdReadable table row"))
    t.eq({ "allow", "deny" }, complete("MdReadable images "))
    t.eq({ "on", "off", "toggle" }, complete("'<,'>MdReadable focus "))
    t.eq({}, complete("MdReadable nav "))
    t.eq({}, complete("MdReadable close "))
    t.eq({}, complete("MdReadable focus on "))
    t.eq({}, complete("MdReadable table format "))
    t.eq({ "focus" }, vim.fn.getcompletion("MdReadable foc", "cmdline"))
    t.eq({ "toggle" }, vim.fn.getcompletion("MdReadable focus t", "cmdline"))
  end)
end
