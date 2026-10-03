# Implementation contracts (I00)

Accepted product specification: `md-readable_design.md`, `docs/final-spec-review.md`.
Run `nvim --headless -u NONE -l tests/run.lua` from the checkout. A test file `tests/test_NAME.lua` returns `function(t)` and registers `t.test(name, fn)`; assertions are `t.eq(expected, actual)` / `t.ok(value)`.

## Coordinates and document

All source/display rows and byte columns are zero-based and ranges half-open. Source ranges use `{start={row,byteColumn}, ["end"]={row,byteColumn}}`. Rendering cell widths are never byte columns. Blocks use `start_row` / `end_row` (exclusive).

`document.parser.parse(lines, opts)` returns `MdReadableDocument` from `types.lua`; opts includes `bufnr`, `changedtick`, `path`. Flat `headings` with parent/children are acceptable; each heading has `range` and `sectionRange`. `links` have `text,target,kind,range,label_start,label_end`. Table parser is `document.table.parse(lines,start_row)` returning `{start_row,end_row,rows,alignments}` or nil. `rows` contains header then data, each `{source_row,cells={{text,start_col,end_col}}}`; delimiter row is `start_row+1` and excluded from rows.

## Render and mapping

`reader.render.render(document, opts)` returns `MdReadableRendered`; opts includes `width`, `table.max_cell_width`, `expanded` keyed by zero-based source row, and `tabs` keyed by source row. `row_map[display_row+1]` is a zero-based source row; `source_rows` lists all contributing original rows when prose is joined. Segments follow `types.lua`: direct text, inline node (full_start/full_end for entire link when full label selected), omission (full source range if the ellipsis is selected). A truncated label marks `node_complete=false`; selecting every visible fragment must not expand a still-incomplete node. Generated borders have no segment. `highlights` are `{row,start_col,end_col,group}` using `MdReadable*` groups. `images` have kind `image` or `mermaid` and source_row/path/alt/code.

Root owns `reader.source_map`: `new(source_lines, rendered)` returns a map with `to_source(row,col) -> row,col`, `to_display(row,col) -> row,col`, `copy(start_row,start_col,end_row,end_col,mode) -> text,regtype` (selection end exclusive; mode char/line/block). Renderers do not require it to render.

## Sessions and services

Root owns `reader.session`, configuration and commands. Session fields and callbacks are in types.lua. Services accept session explicitly, never assume current buffer is the original. `session:jump_source(row,col)` moves the reading cursor; `session:navigate(path,anchor)` resolves document targets; `session:refresh()` rerenders unsaved source. Root publishes `require('md-readable.reader.session').current()` and `.all()`.

Focus: `reader.focus.set(session, enabled, range?)`, `.update(session)`, `.close(session)`.
Theme: `ui.theme.apply(win, name, opts?)`, `.setup()`.
Minimap: `nav.minimap.open(session)`, `.close(session)`, `.update(session)`, `.toggle(session)`, `.set_annotations(session, provider_id, items)`; items are `{start_row,end_row,kind,severity?}` in original coordinates. Git/diagnostic updates are service-owned and must be cleaned up. Mini buffers can map Enter to session:jump_source.
Table: `table.format.format(table) -> lines`; `table.edit.edit(table, action, index, count) -> lines,err` actions row_before/row_after/row_delete/col_before/col_after/col_delete; index is 1-based data row (header 0) or column. `table.prefix` preserves the source container/indent spelling and is prepended by the formatter. Root applies edit to `[start_row,end_row)` exactly once and refreshes. `format` must not mutate its argument.

## Navigation

Snapshot matches design: `{schemaVersion=1,rootDir,adapterId,trees={{id,title,items}},orderOrigin,diagnostics}`; nodes `{id,title,target?,children,source?}`; document target `{type='document',path,anchor?}`.
`navigation.model.validate(snapshot) -> boolean,diagnostics`;
`navigation.index.build(tree) -> {by_id,by_path,parent,order}`;
`navigation.order.reading_order(tree,root_dir) -> nodes` (file availability injectable as third argument for tests);
`navigation.order.adjacent(tree,node_id,direction,root_dir) -> node?`.
`navigation.detect.load(path,opts) -> {status,snapshot?,diagnostics,candidates?}`; opts may set root_dir,adapter,provider. Each `adapters.NAME.parse(ctx)` accepts `{root_dir,read=function(path)->lines?,config_path?}`; supports direct return and remains UI-independent. Parse routines MUST reject unsupported dynamic syntax rather than execute it. Root can schedule/cache load results and present candidate choices.

## Ownership

Root: config/init/plugin/session/source_map/yank/search/navigation UI, issue publication, docs, media and integrations after first wave.
Rendering agent: document/, renderers/, reader/render.lua, tests/test_document.lua, tests/test_render.lua, dedicated fixtures.
Navigation agent: parsers/, adapters/, navigation/{model,index,order,detect,resolver}.lua, providers/navigation.lua, tests/test_navigation.lua and dedicated fixtures.
Services agent: reader/focus.lua, ui/theme.lua, table/, nav/minimap.lua, minimap/, tests/test_services.lua and dedicated fixtures.

Shared files and this contract are changed only by root. Send proposed changes to root before changing an interface. No agent edits another agent's files. Each works in a separate checkout and commits only assigned files. Preserve licenses when adapting reference code.
