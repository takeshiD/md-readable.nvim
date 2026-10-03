# md-readable.nvim

[日本語版](README_ja.md)

A Neovim plugin specialized in making Markdown easy to read.
Read Markdown in a separate, read-only view while keeping the original text and unsaved edits intact. The implementation includes the features below; SSG support covers the [documented static subsets](tests/fixtures/navigation/SUPPORTED.md).

- Appearance
    - Markdown syntax highlighting
    - Table rendering
    - Code blocks
    - Color theme switching for the reading view only
    - Truncated display of long text in tables / URLs
    - Distinct icons for local links and external links
- Navigation
    - Minimap
        - Git changes and LSP diagnostics mapped from the source
    - Heading tree
    - Focus Mode
    - Table of contents and previous/next navigation for major SSGs
        - mdBook, Docusaurus, MkDocs, Zensical, Astro/Starlight, HonKit, GitBook
- Formatting
    - Table formatting
    - Explicit table row and column insertion/deletion
- Contents
    - Image display (png, jpg, svg, webp, etc.)
    - Mermaid diagram rendering
- Integration
    - Telescope and Snacks previewers (optional picker dependencies)

Some writing support is also included.
- Writing
    - Bidirectional cursor and page synchronization between the Read Buffer and the Write Buffer

The reading view will search displayed text with `/` and copy the corresponding Markdown source with `y`. Selecting part of a link label copies that text; selecting the entire label copies the original Markdown link. A separate command will search the full source, including omitted content. Reading positions will not be persisted across Neovim sessions.

The reference plugins listed in AGENTS.md are implementation references, not required dependencies. Rendering, Focus, table editing, and the minimap are implemented inside this plugin.

See the [agreed specification](docs/final-spec-review.md), [implementation tracker](https://github.com/takeshiD/md-readable.nvim/issues/33), and [verification notes](docs/verification.md).

# Requirements
- Neovim >= 0.12
- Inline images require a compatible Kitty graphics terminal. WezTerm/Ghostty are targets; actual terminal pixels are not yet manually verified.
- Optional: ImageMagick/rsvg-convert/FFmpeg for image conversion; installed `mmdc` for Mermaid; `curl` for explicitly allowed web images; `git` for minimap changes.
- Telescope and Snacks are optional, only for their preview integrations. No reference plugin is required and no tool is automatically installed.

# Quick start

Load this repository with your plugin manager. For example, while this implementation is on its feature branch:

```lua
{
  "takeshiD/md-readable.nvim",
  branch = "feat/readable-implementation",
  opts = {},
}
```

Open a Markdown file and run one of:

```vim
:MdReadable          " use the current window
:MdReadable vert     " original on the left, reading view on the right
:MdReadable float    " floating reading view
:MdReadable source   " return to the corresponding original position
:MdReadable close
```

Setup is optional. Assign commands to your own keys or autocmds; the plugin does not install global keymaps. In reading buffers, `y` copies source Markdown and Ctrl-O/Ctrl-I use the original-document jumplist. `/`, `?`, `n`, and `N` search the displayed text.

| Command after `MdReadable` | Action |
| --- | --- |
| `nav`, `outline`, `select` | Book tree, page headings, adapter/tree selection |
| `prev`, `next`, `heading-prev`, `heading-next` | Chapter/heading navigation |
| `links`, `open` | Link list or open the item/cell under the cursor |
| `search [pattern]` | Search the complete original, including hidden text |
| `focus on/off/toggle` | Limelight-style paragraph focus; a visual range fixes the focused lines |
| `theme default/dark/light` | Change only the reading window's colors |
| `minimap on/off/toggle/focus` | Minimap with Git/LSP annotations; Enter jumps to the document |
| `table format` | Align the original table explicitly |
| `table row-before/row-after/row-delete [count]` | Insert/delete data rows |
| `table col-before/col-after/col-delete [count]` | Insert/delete columns |
| `expand`, `tab [index]` | Expand omitted content or select a static tab |
| `images allow/deny` | Permit/deny web image retrieval for this reading session |
| `refresh`, `diagnostics` | Reload structure or inspect navigation/media errors |

Table edits are undoable and do not save the file. Decoration-only selections do not overwrite registers. Selecting a cell's ellipsis copies the complete original cell.

# Configuration

```lua
require("md-readable").setup({
  layout = "integrated", -- integrated, separate, ondemand
  width = 100,
  keymaps = false, -- true adds q and Enter only in reading buffers
  table = { max_cell_width = 28 },
  focus = { coefficient = 0.5, span = 0 },
  minimap = { width = 14, mode = "braille", git = true, diagnostic = true },
  images = { enabled = true, remote = false, height = 10 },
  mermaid = { command = "mmdc" },
  -- adapters = { adapter = "mdbook", root_dir = "/path/to/book" },
})
```

At narrow widths, navigation uses a floating chooser to preserve the reading area. Nerd Font glyphs are not required; an ASCII minimap mode is available. Git annotations compare the index with the original buffer, including unsaved changes. Diagnostics come from Neovim's standard diagnostic API.

Dynamic SSG configuration is not executed. Supply a custom Lua/JSON navigation provider when needed; see `:help md-readable-providers` and the [SSG compatibility table](tests/fixtures/navigation/SUPPORTED.md).

# Picker previews

```lua
local previewer = require("md-readable.integrations.telescope").previewer()
require("telescope.builtin").find_files({ previewer = previewer })

require("snacks").setup({
  picker = { preview = require("md-readable.integrations.snacks").preview() },
})
```

`:Telescope md_readable find_files` and `:Telescope md_readable live_grep` are also available. Preview integrations preserve the picker's selection action and fall back to its normal preview for unsupported files. See `:help md-readable` and `:checkhealth md-readable`.

# Development

```sh
nvim --headless -n -u NONE -i NONE -l tests/run.lua
```

Tests cover parsers, all seven static SSG adapters, actual reading sessions, source copying, synchronization, narrow layouts, table edits, Git/LSP annotations, media protocols and cancellation, and installed picker integrations when available. See [verification notes](docs/verification.md) for the remaining real-terminal/Mermaid checks.

# License
MIT
