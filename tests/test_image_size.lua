return function(t)
  local config = require("md-readable.config")
  local display = require("md-readable.image.display")
  local provider = require("md-readable.providers.image")
  -- Runs fn with cells of 10x20 pixels, whatever the terminal is.
  local function with_cells(fn)
    local cell_size = display.cell_size
    display.cell_size = function()
      return { width = 10, height = 20 }
    end
    local ok, err = pcall(fn)
    display.cell_size = cell_size
    assert(ok, err)
  end

  t.test("images fit their box like snacks.image and are never enlarged", function()
    with_cells(function()
      t.eq({ 30, 5 }, { display.fit(300, 100, 80, 40) }, "small images keep their own size")
      t.eq({ 80, 8 }, { display.fit(1600, 320, 80, 40) }, "wide images fill the width")
      t.eq({ 20, 20 }, { display.fit(400, 800, 80, 20) }, "tall images fill the height")
      t.eq({ 80, 14 }, { display.fit(1200, 420, 80, 40, true) }, "diagrams may be enlarged")
    end)
  end)

  t.test("the image box follows images.width/height and their bounds", function()
    local session = { config = { images = {} }, read_win = vim.api.nvim_get_current_win() }
    local height = vim.api.nvim_win_get_height(0)
    t.eq({ 80, height }, { provider.box(session, { width = 80 }) }, "body width and window height")
    session.config.images = { max_width = 50, max_height = 6 }
    t.eq({ 50, 6 }, { provider.box(session, { width = 80 }) })
    session.config.images = { width = 120, height = 12 }
    t.eq({ 80, 12 }, { provider.box(session, { width = 80 }) }, "never wider than the body")
    session.config.images = { width = 10, min_width = 30, height = 2, min_height = 4 }
    t.eq({ 30, 4 }, { provider.box(session, { width = 80 }) })
  end)

  t.test("a local PNG reserves the rows of its fitted size", function()
    with_cells(function()
      local dir = t.tempdir()
      local path = dir .. "/wide.png"
      -- 1600x320 PNG header (the pixels are never read)
      local header = "\137PNG\13\10\26\10\0\0\0\13IHDR\0\0\6\64\0\0\1\64"
      local fd = assert(vim.uv.fs_open(path, "w", 420))
      vim.uv.fs_write(fd, header, 0)
      vim.uv.fs_close(fd)
      local session = {
        config = { images = { max_height = 40 } },
        read_win = vim.api.nvim_get_current_win(),
        document = { path = dir .. "/doc.md" },
      }
      t.eq(8, provider.rows(session, { kind = "image", path = "wide.png", width = 80 }))
      session.config.images.max_width = 40
      t.eq(4, provider.rows(session, { kind = "image", path = "wide.png", width = 80 }), "the size is remembered")
      t.eq(nil, provider.rows(session, { kind = "image", path = "missing.png", width = 80 }))
    end)
  end)

  t.test("setup validates image sizes", function()
    local saved = config.options
    t.ok(not pcall(config.setup, { images = { max_width = 0 } }))
    t.ok(not pcall(config.setup, { images = { height = "10" } }))
    t.ok(pcall(config.setup, { images = { width = 60, max_height = 20 } }))
    config.options = saved
  end)
end
