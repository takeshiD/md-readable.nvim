# Real Session navigation validation

Run `nvim --headless -u NONE -l tests/run.lua`. `tests/test_end_to_end.lua` invokes the actual Session, document parser, renderer, source map, mdBook adapter, navigation model, resolver, and sidebar/pager. It creates real temporary project files and Neovim windows; no Session or adapter mock replaces the integration.

Verified on 2026-10-04 with Neovim 0.12.5:

- Same-window, vertical, and floating readers: next/previous chapters synchronize the paired source, preserve unsaved buffers and disk contents, stop at first/last, and clean up reader buffers.
- Native cursor events synchronize source and rendered coordinates in both directions. Assertions use the source map and tolerate renderers changing display line counts.
- Real parsed heading anchors include repeated `repeat`/`repeat-1` slugs and Japanese titles; links and Session navigation reach the corresponding mapped heading.
- Integrated/separate/ondemand layouts remain usable at 120, 80, and 60 columns. Narrow layouts defer automatic sidebars and open an explicit floating chooser. User statusline and source buffers survive.
- Repeated references to one document retain distinct navigation occurrences without injecting page headings into the book model.
- Unsupported unsaved configuration preserves the old snapshot with a stale marker; correcting it replaces the snapshot and restores navigation.
- A normal mdBook layout with `book.toml` above `chapters/SUMMARY.md` is automatically detected. SUMMARY-only ambiguity is a fallback after checking ancestor configuration files, so the source directory no longer hides the actual project root.

## Observed benchmark

The benchmark creates 1,000 Markdown files and a SUMMARY referencing them, then times the first actual `Session.open('current')` and a subsequent `load_navigation()` plus `refresh()`. The integrated sidebar is enabled. Fixture creation is excluded; the Lua runtime is already loaded by the suite, and files have just been written, so this is not a cold-storage benchmark.

One observed run on this development environment:

| Operation | Elapsed |
| --- | ---: |
| First Session.open, 1,000-page book | 49.87 ms |
| Reparse and refresh | 45.93 ms |

The suite prints fresh measurements on each run and verifies all 1,000 document targets. These observations are not latency guarantees or pass/fail thresholds. Full suite after these additions: 126 tests, zero failures. Real terminal appearance and graphics protocols are outside this headless validation.
