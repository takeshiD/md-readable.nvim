# Verification

Implementation and verification date: 2026-10-04. Neovim: 0.12.5 (LuaJIT).

## Automated checks

Run from the repository root:

```sh
nvim --headless -n -u NONE -i NONE -l tests/run.lua
```

The runner reports the exact number of executed tests and exits nonzero on a failure. Optional real Telescope/Snacks tests run when installed; protocol and lifecycle tests do not require an image terminal.

Latest full run in this environment: **150 tests, 0 failures**. StyLua checks, `git diff --check`, help-tag generation, `:checkhealth md-readable`, and an actual command-line `MdReadable` → Focus → source smoke flow also passed.

Covered behavior includes Markdown and static extensions, source byte ranges and copying, all seven SSG adapters, ambiguous detection and errors, real reading sessions in current/vertical/floating windows, unsaved changes, native jump history, missing anchors, original table edits, theme and Focus isolation, minimap Git/LSP annotations, narrow layouts, media conversion/caching/cancellation, and picker cleanup. Named/append/black-hole registers and UTF-8 rectangular copying are exercised through actual Neovim yank operations.

Real installed Telescope and Snacks APIs were exercised. ImageMagick was used to convert actual SVG/JPEG/WebP data. A real temporary Git repository validates index changes and unsaved buffer diffs. Media protocol tests intercept terminal output; Mermaid process tests use a controlled executable fixture.

## Performance observation

An actual mdBook fixture with 1,000 Markdown files and integrated sidebar took approximately 50 ms for initial Session.open and 47 ms for load_navigation + refresh on this environment, excluding fixture creation. These are observations, not latency guarantees. The fixture and measurement are in `tests/test_end_to_end.lua`; context is in `tests/fixtures/navigation/END_TO_END.md`.

## Still requiring environment verification

- Actual image pixels, scroll cropping, resize, split/floating overlap and cleanup on WezTerm and Ghostty. This execution environment has no attached graphical terminal for visual verification.
- Actual Mermaid CLI rendering. `mmdc` is not installed here. It was not automatically downloaded; absent-tool fallback and the renderer process contract are tested.

The image/Mermaid implementations are present, but these real-environment checks remain open in the corresponding GitHub issues and the final integration issue. Do not describe these checks as passed.

## Compatibility boundaries

See `tests/fixtures/navigation/SUPPORTED.md` for exact static parser/SSG subsets and limitations. HTML details and tab components are static multiline forms; arbitrary components are shown as source, never executed. Images need a compatible terminal and optional local converters. Missing tools leave readable alt text or code.
