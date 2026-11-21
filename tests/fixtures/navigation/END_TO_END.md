# Real Session navigation validation

Run `nvim --headless -u NONE -l tests/run.lua`. `tests/test_end_to_end.lua` invokes the actual Session, document parser, renderer, source map, mdBook adapter, navigation model, resolver, and sidebar/pager. It creates real temporary project files and Neovim windows; no Session or adapter mock replaces the integration.

Updated for Issue #52 on 2026-11-21 with Neovim 0.12.6:

- Same-window, vertical, and floating readers: next/previous chapters synchronize the paired source, preserve unsaved buffers and disk contents, stop at first/last, and clean up reader buffers.
- Native cursor events synchronize source and rendered coordinates in both directions. Assertions use the source map and tolerate renderers changing display line counts.
- Real parsed heading anchors include repeated `repeat`/`repeat-1` slugs and Japanese titles; links and Session navigation reach the corresponding mapped heading.
- Legacy integrated/separate/ondemand inputs all use one initially closed panel at 120, 80, and 60 columns. Explicit opening chooses a sidebar or float from available width; resize preserves selection, folds, focus, source buffers and the user statusline.
- Repeated references to one document retain distinct navigation occurrences without injecting page headings into the book model.
- Unsupported unsaved configuration preserves the old snapshot with a stale marker; correcting it replaces the snapshot and restores navigation.
- A normal mdBook layout with `book.toml` above `chapters/SUMMARY.md` is automatically detected. SUMMARY-only ambiguity is a fallback after checking ancestor configuration files, so the source directory no longer hides the actual project root.

## Observed benchmark

The benchmark creates 1,000 Markdown files and a SUMMARY referencing them, then times reader startup and the first navigation toggle. Fixture creation is excluded; the Lua runtime is already loaded and files were just written, so this is not a cold-storage benchmark.

Before Issue #52, reader startup with automatic contents took 51.46 ms in an observed run. After lazy loading, startup took 1.42 ms and the first explicit navigation toggle took 51.24 ms. This moves work to first use; it does not make parsing itself faster. These are observations, not latency guarantees or test thresholds.

## Real TUI smoke

Run `nvim --headless -n -u NONE -i NONE -l tests/pty_navigation.lua`. It starts a separate Neovim TUI in a PTY, responds to terminal capability detection and waits for VimEnter before driving it through RPC and actual mapped input. It selects a heading before resizing 120 → 60 → 120 → 60 columns, verifies the same selection and focus, then presses Enter. It also verifies page selection, Escape, closed-state persistence and source preservation. This checks real window/input behavior; it does not assess visual appearance or graphics protocols.
