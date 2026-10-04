return function(t)
  local api = require("md-readable")
  local sessions = require("md-readable.reader.session")
  local capabilities = require("md-readable.image.capabilities")
  local convert = require("md-readable.image.convert")
  local display = require("md-readable.image.display")
  local provider = require("md-readable.providers.image")
  local parse = require("md-readable.document.parser").parse
  local render = require("md-readable.reader.render").render
  local png =
    vim.base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/Z1cAAAAASUVORK5CYII=")
  local function cleanup()
    for _, s in ipairs(vim.tbl_values(sessions.all())) do
      sessions.close(s)
    end
    vim.cmd("silent! only!")
  end
  -- Runs fn with a graphics-capable terminal and stubbed conversion/display.
  local function with_media(converted, fn)
    local get, ensure, show = capabilities.get, convert.ensure, display.show
    capabilities.get = function()
      return true
    end
    convert.ensure = function(path, _, callback)
      if converted then
        callback(path)
      else
        callback(nil, "conversion failed")
      end
      return function() end
    end
    display.show = function()
      return 1, function() end
    end
    local ok, err = pcall(fn)
    capabilities.get, convert.ensure, display.show = get, ensure, show
    cleanup()
    assert(ok, err)
  end
  local function open(dir, lines)
    cleanup()
    api.setup({
      navigation = { auto_open = false },
      images = { enabled = true, height = 5, cache_dir = dir .. "/cache" },
      mermaid = { command = dir .. "/missing-mmdc" },
      debounce = 0,
    })
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, dir .. "/doc.md")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return api.open("current")
  end
  local function blank_rows(s)
    local count = 0
    for _, line in ipairs(vim.api.nvim_buf_get_lines(s.read_buf, 0, -1, false)) do
      if line == "" then
        count = count + 1
      end
    end
    return count
  end

  t.test("render reserves rows only for media the predicate accepts", function()
    local doc = parse({ "![a](a.png)", "", "```mermaid", "graph TD", "```", "after" })
    local rejected = render(doc, {
      media = {
        image_height = 4,
        reserve = function()
          return false
        end,
      },
    })
    local trimmed = vim.tbl_map(function(line)
      return (line:gsub("%s+$", ""))
    end, rejected.lines)
    t.eq({ "[Image: a]", "", " mermaid", " graph TD", "", "after" }, trimmed)
    t.eq({ 0, 0 }, { rejected.images[1].height, rejected.images[2].height })
    local accepted = render(doc, {
      media = {
        image_height = 4,
        reserve = function()
          return true
        end,
      },
    })
    t.eq(#rejected.lines + 8, #accepted.lines)
  end)

  t.test("missing images and absent mmdc never reserve blank rows", function()
    local dir = t.tempdir()
    with_media(true, function()
      local s = open(dir, { "![alt text](img.png)", "", "```mermaid", "graph TD; A-->B", "```", "", "Following text" })
      t.eq(2, blank_rows(s), "only the two source blank lines remain")
      t.eq(0, s.rendered.images[1].height)
      t.eq(0, s.rendered.images[2].height)
      local errors = table.concat(provider.errors(s), "\n")
      t.ok(errors:find("img.png: image file does not exist", 1, true), errors)
      t.ok(errors:find("Mermaid diagram (line 3): install mmdc", 1, true), errors)
      local last = #s.rendered.lines - 1
      t.eq("Following text", s.rendered.lines[last + 1])
      t.eq(6, (s.map:to_source(last, 0)))
      local fd = assert(vim.uv.fs_open(dir .. "/img.png", "w", 420))
      vim.uv.fs_write(fd, png, 0)
      vim.uv.fs_close(fd)
      s:refresh()
      t.eq(5, s.rendered.images[1].height, "an existing file reserves rows")
    end)
  end)

  t.test("a failed conversion releases its rows and keeps the source map", function()
    local dir = t.tempdir()
    local fd = assert(vim.uv.fs_open(dir .. "/bad.png", "w", 420))
    vim.uv.fs_write(fd, png, 0)
    vim.uv.fs_close(fd)
    with_media(false, function()
      local s = open(dir, { "Intro", "", "![broken](bad.png)", "", "Following text" })
      t.ok(
        vim.wait(1000, function()
          return s.rendered.images[1].height == 0
        end, 10),
        "rows released after failure"
      )
      t.eq({ "Intro", "", "[Image: broken]", "", "Following text" }, s.rendered.lines)
      t.eq(4, (s.map:to_source(4, 0)))
      vim.api.nvim_win_set_cursor(s.read_win, { 5, 0 })
      vim.cmd("normal yy")
      t.eq("Following text\n", vim.fn.getreg('"'))
      t.ok(table.concat(provider.errors(s), "\n"):find("bad.png: conversion failed", 1, true))
    end)
  end)
end
