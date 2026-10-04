local M = {}
local namespace = vim.api.nvim_create_namespace("md-readable-links")
-- Short kind tags shown at the end of each row, so kinds never rely on color.
local tags = {
  external = "web",
  document = "doc",
  anchor = "anchor",
  asset = "file",
  image = "image",
  unresolved = "missing",
}

function M.follow(session, link)
  if link.kind == "footnote" then
    session:jump_source(link.definition_row, 0)
    return
  end
  local resolved = require("md-readable.navigation.resolver").resolve(link.target, {
    path = vim.api.nvim_buf_get_name(session.source_buf),
    root_dir = session.snapshot and session.snapshot.rootDir,
    snapshot = session.snapshot,
    headings = session.document.headings,
  })
  if not resolved then
    vim.notify("md-readable: unresolved link", vim.log.levels.WARN)
    return
  end
  if resolved.type == "document" then
    session:navigate(resolved.path, resolved.anchor)
  elseif resolved.type == "external" then
    vim.ui.open(resolved.url)
  elseif resolved.type == "asset" then
    vim.ui.open(resolved.path)
  else
    vim.notify("md-readable: " .. (resolved.reason or "unresolved link"), vim.log.levels.WARN)
  end
end

function M.close(session)
  local panel = session._links_panel
  session._links_panel = nil
  if panel and vim.api.nvim_win_is_valid(panel.win) then
    pcall(vim.api.nvim_win_close, panel.win, true)
  end
  if session.read_win and vim.api.nvim_win_is_valid(session.read_win) then
    vim.api.nvim_set_current_win(session.read_win)
  end
end

-- Rows are "label  target  [kind]" clipped to width. Returns the lines, the
-- link of each row and the byte offsets used for highlighting.
function M.rows(links, width)
  local clip = require("md-readable.ui.navigation").clip
  local lines, entries, marks = { "Links", "Enter open  o show in text  q close" }, {}, {}
  for _, link in ipairs(links) do
    local tag = "[" .. (tags[link.kind] or link.kind or "link") .. "]"
    local label = link.text ~= "" and link.text or tostring(link.target)
    local room = math.max(8, width - vim.fn.strdisplaywidth(tag) - 1)
    local label_text = clip(label, math.max(4, math.min(vim.fn.strdisplaywidth(label), math.floor(room / 2))))
    local target_text = clip(tostring(link.target), math.max(4, room - vim.fn.strdisplaywidth(label_text) - 2))
    local body = label_text .. "  " .. target_text
    local pad = math.max(1, width - vim.fn.strdisplaywidth(body) - vim.fn.strdisplaywidth(tag))
    lines[#lines + 1] = body .. string.rep(" ", pad) .. tag
    entries[#lines] = link
    marks[#lines] = { label = #label_text, target = #body, tag = #body + pad }
  end
  if #links == 0 then
    lines[#lines + 1] = "No links in this document."
  end
  return lines, entries, marks
end

-- Floating list with the outline panel's look and keys.
function M.open(session)
  M.close(session)
  local links = vim.tbl_filter(function(link)
    return link.kind ~= "footnote"
  end, session.document.links or {})
  local width = math.max(20, math.min(vim.o.columns - 4, math.max(40, math.floor(vim.o.columns * 0.7))))
  local lines, entries, marks = M.rows(links, width)
  local height = math.max(3, math.min(vim.o.lines - 5, #lines, math.floor(vim.o.lines * 0.75)))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "md-readable-links"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = "minimal",
    border = "single",
    zindex = 60,
  })
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = "Normal:Normal,CursorLine:Visual"
  session._links_panel = { buf = buf, win = win, entries = entries }
  vim.api.nvim_buf_set_extmark(buf, namespace, 0, 0, { end_row = 1, hl_group = "Title", hl_eol = true })
  vim.api.nvim_buf_set_extmark(buf, namespace, 1, 0, { end_row = 2, hl_group = "Comment", hl_eol = true })
  for row, mark in pairs(marks) do
    local function hl(a, b, group)
      vim.api.nvim_buf_set_extmark(buf, namespace, row - 1, a, { end_col = b, hl_group = group })
    end
    hl(0, mark.label, "MdReadableLink")
    hl(mark.label, mark.target, "MdReadableMuted")
    hl(mark.tag, #lines[row], "MdReadableLinkIcon")
  end
  vim.api.nvim_win_set_cursor(win, { math.min(3, #lines), 0 })
  local function selected()
    return entries[vim.api.nvim_win_get_cursor(win)[1]]
  end
  local function key(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = desc })
  end
  key("<CR>", function()
    local link = selected()
    if link then
      M.close(session)
      if not session.closed then
        M.follow(session, link)
      end
    end
  end, "Open the selected link")
  key("o", function()
    local link = selected()
    if link then
      M.close(session)
      session:jump_source(link.range.start.row, link.range.start.byteColumn)
    end
  end, "Show the link in the document")
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    key(lhs, function()
      M.close(session)
    end, "Close the link list")
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if session._links_panel and session._links_panel.win == win then
          session._links_panel = nil
          pcall(vim.api.nvim_win_close, win, true)
        end
      end)
    end,
  })
  return win
end
return M
