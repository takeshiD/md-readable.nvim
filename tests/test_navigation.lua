return function(t)
  local Y = require('md-readable.parsers.yaml')
  local T = require('md-readable.parsers.toml')
  local S = require('md-readable.parsers.sidebar_static')
  local C = require('md-readable.adapters.common')
  local Index = require('md-readable.navigation.index')
  local Order = require('md-readable.navigation.order')
  local function fixture(files)
    local root = t.tempdir()
    for path, lines in pairs(files) do t.write(root .. '/' .. path, type(lines) == 'string' and vim.split(lines, '\n', { plain = true }) or lines) end
    return root
  end
  local function parse(adapter, files, opts)
    local root = fixture(files)
    local result = require('md-readable.adapters.' .. adapter).parse(vim.tbl_extend('force', { root_dir = root }, opts or {}))
    return result, root
  end
  local function paths(result, tree)
    t.ok(result.snapshot, vim.inspect(result))
    local out = {}
    for _, node in ipairs(Order.reading_order(result.snapshot.trees[tree or 1], result.snapshot.rootDir)) do out[#out + 1] = node.target.path end
    return out
  end
  t.test('YAML ordered nested mappings, sequence continuation, comments and quoted keys', function()
    local data, errors = Y.parse({
      'docs_dir: "日本語 docs" # keep space', 'nav:', '  - "Start: here": start.md',
      '  - Guide:', '      - Intro: guide/index.md', '      - "More": "guide/more.md#part"',
      'site:', '  structure:', '    - type: space', '      key: main', '      content:', '        directory: docs',
      'flags: [true, false, null]', 'quoted: "hash # value"',
    }, 'mkdocs.yml')
    t.eq({}, errors); t.eq('日本語 docs', data.docs_dir)
    t.eq({ 'docs_dir', 'nav', 'site', 'flags', 'quoted' }, Y.keys(data))
    t.eq('guide/more.md#part', data.nav[2].Guide[2].More)
    t.eq('docs', data.site.structure[1].content.directory)
    t.eq({ true, false, vim.NIL }, data.flags)
  end)
  t.test('YAML rejects aliases, tags, merges and duplicate keys with source rows', function()
    for _, text in ipairs({ 'x: !ENV NAME', 'x: &default value', 'x: *default', 'x:\n  <<: *base', 'x: 1\nx: 2' }) do
      local data, errors = Y.parse(text, 'test.yml')
      t.eq(nil, data); t.ok(#errors > 0); t.eq('test.yml', errors[1].source.path)
    end
  end)
  t.test('TOML project nav multiline arrays, quoted inline keys, headers and array tables', function()
    local data, errors = T.parse({ '[project]', 'docs_dir = "content"', 'nav = [', ' { "Home" = "index.md" },', ' { "Guide" = ["one.md", "two.md"] }, # order', ']', '[project.theme]', 'features = ["toc.follow"]', '[[items]]', 'name = "a"', '[[items]]', 'name = "b"' }, 'zensical.toml')
    t.eq({}, errors); t.eq('content', data.project.docs_dir)
    t.eq('two.md', data.project.nav[2].Guide[2]); t.eq('b', data.items[2].name)
  end)
  t.test('static JS/TS supports declarations, imports, objects and rejects evaluation', function()
    local data, errors = S.parse({ "import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';", "const sidebars: SidebarsConfig = { main: ['intro', {Guide: ['guide/start']}], other: [] };", 'export default sidebars;' }, 'sidebars.ts')
    t.eq({}, errors); t.eq('guide/start', data.main[2].Guide[1])
    for _, text in ipairs({ "module.exports = makeSidebar()", "export default {main: [...other]}", "export default {main: [process.exit()]}" }) do
      local bad, diagnostics = S.parse(text); t.eq(nil, bad); t.ok(#diagnostics > 0)
    end
  end)
  t.test('SUMMARY preserves part headings, prefix/suffix, drafts and nested links', function()
    local items, errors = require('md-readable.parsers.summary').parse({ '# Summary', '[Foreword](前書き.md)', '# Part One', '- [Chapter](chapter.md#hello)', '  - [Child](<space name.md>)', '- [Draft]()', '[After](after.md)' }, 'SUMMARY.md')
    t.eq({}, errors); t.eq('heading', items[3].kind)
    t.eq('space name.md', items[4].children[1].target); t.eq('', items[5].target)
    t.eq(3, items[4].source.row); t.eq(false, items[6].numbered)
  end)
  t.test('navigation validates cycles/duplicate IDs and preserves duplicate document occurrences', function()
    local a = { id = 'a', title = 'A', target = { type = 'document', path = 'a.md' }, children = {} }
    local b = { id = 'b', title = 'B', target = { type = 'document', path = 'a.md' }, children = {} }
    a.children = { b }
    local tree = { id = 'main', title = 'Main', items = { a } }
    local snapshot = { schemaVersion = 1, rootDir = '/tmp', adapterId = 'test', trees = { tree }, orderOrigin = 'custom', diagnostics = {} }
    t.eq(true, require('md-readable.navigation.model').validate(snapshot))
    local index = Index.build(tree)
    t.eq(2, #index.by_path['a.md']); t.eq(b, Index.resolve_current('a.md', { index = index, history = { ['a.md'] = 'b' } }))
    t.eq({ a, b }, Index.breadcrumbs(index, 'b'))
    t.eq({ a, b }, Order.reading_order(tree, '/tmp', function() return true end))
    t.eq(nil, Order.adjacent(tree, 'a', 'previous', '/tmp', function() return true end))
    t.eq(nil, Order.adjacent(tree, 'unlisted', 'next', '/tmp', function() return true end))
    b.children = { a }; t.eq(false, require('md-readable.navigation.model').validate(snapshot))
    b.children = {}; b.id = 'a'; t.eq(false, require('md-readable.navigation.model').validate(snapshot))
  end)
  t.test('mdBook source root, parent/child order, parts and unavailable drafts', function()
    local result = parse('mdbook', {
      ['book.toml'] = '[book]\ntitle = "My book"\nsrc = "chapters"',
      ['chapters/SUMMARY.md'] = '# Summary\n[Foreword](intro.md)\n# Part\n- [Parent](parent.md)\n  - [Child](child.md)\n- [Draft]()\n- [Missing](missing.md)\n[After](after.md)',
      ['chapters/intro.md'] = '# Intro', ['chapters/parent.md'] = '# Parent', ['chapters/child.md'] = '# Child', ['chapters/after.md'] = '# After',
    })
    t.eq({ 'chapters/intro.md', 'chapters/parent.md', 'chapters/child.md', 'chapters/after.md' }, paths(result))
    t.eq('partial', result.status); t.eq('unavailable', result.snapshot.trees[1].items[2].children[2].target.type)
  end)
  t.test('HonKit root/custom SUMMARY and dynamic config rejection', function()
    local result = parse('honkit', { ['book.json'] = '{"root":"manuscript","structure":{"summary":"TOC.md"}}', ['manuscript/TOC.md'] = '# Contents\n* [One](one.md)\n  * [Two](two.md)', ['manuscript/one.md'] = '# One', ['manuscript/two.md'] = '# Two' })
    t.eq({ 'manuscript/one.md', 'manuscript/two.md' }, paths(result)); t.eq('ok', result.status)
    local empty = parse('honkit', { ['book.json'] = '{}', ['SUMMARY.md'] = '# Summary' }); t.eq('ok', empty.status); t.eq({}, paths(empty))
    local dynamic = parse('honkit', { ['book.js'] = 'module.exports = require("./generated")' }); t.eq('unsupported', dynamic.status)
  end)
  t.test('GitBook multiple local and unsynced spaces with nested root and custom summary', function()
    local result = parse('gitbook', {
      ['gitbook-docs.yaml'] = 'site:\n  title: Site\n  structure:\n    - type: section\n      key: guides\n      children:\n        - type: space\n          key: en\n          title: English\n          content:\n            directory: spaces/en\n        - type: space\n          key: remote\n          title: Remote\n          content:\n            directory: null',
      ['spaces/en/.gitbook.yaml'] = 'root: content\nstructure:\n  summary: TOC.md',
      ['spaces/en/content/TOC.md'] = '# Summary\n## Product\n* [Actual title](intro.md "Navigation label")',
      ['spaces/en/content/intro.md'] = '# Intro',
    })
    t.eq({ 'spaces/en/content/intro.md' }, paths(result)); t.eq(2, #result.snapshot.trees)
    t.eq('Navigation label', result.snapshot.trees[1].items[1].children[1].title)
    t.eq('unavailable', result.snapshot.trees[2].items[1].target.type)
  end)
  t.test('MkDocs docs_dir/ordered hierarchy/external links and absent nav inference', function()
    local result = parse('mkdocs', { ['mkdocs.yml'] = 'site_name: Docs\ndocs_dir: content\nnav:\n  - Home: index.md\n  - Guide:\n    - Second: second.md\n    - First: first.md\n  - Web: https://example.com', ['content/index.md'] = '# Home', ['content/second.md'] = '# Second', ['content/first.md'] = '# First' })
    t.eq({ 'content/index.md', 'content/second.md', 'content/first.md' }, paths(result)); t.eq('external', result.snapshot.trees[1].items[3].target.type)
    local inferred = parse('mkdocs', { ['mkdocs.yml'] = 'site_name: Docs', ['docs/z.md'] = '# Z', ['docs/a.md'] = '# A' })
    t.eq('inferred', inferred.snapshot.orderOrigin); t.eq('partial', inferred.status)
  end)
  t.test('Zensical project nav TOML has real document mapping and order', function()
    local result = parse('zensical', { ['zensical.toml'] = '[project]\nsite_name = "Docs"\ndocs_dir = "content"\nnav = [ {Home = "index.md"}, {Guide = ["second.md", "first.md"]}, {Web = "https://example.com"} ]', ['content/index.md'] = '# Home', ['content/second.md'] = '# Second', ['content/first.md'] = '# First' })
    t.eq({ 'content/index.md', 'content/second.md', 'content/first.md' }, paths(result)); t.eq('zensical', result.snapshot.adapterId)
  end)
  t.test('Docusaurus static sidebar IDs differ from slugs and support multiple sidebars', function()
    local result = parse('docusaurus', {
      ['docusaurus.config.js'] = "export default {presets: [['classic', {docs: {path: 'content', sidebarPath: './sidebars.js'}}]]};",
      ['sidebars.js'] = "module.exports = {main: ['intro', {type:'category', label:'Guide', link:{type:'doc', id:'guide/start'}, items:['guide/next']}], secondary:['intro']};",
      ['content/01-intro.md'] = '---\nslug: /totally-different\n---\n# Intro',
      ['content/guide/01-first.md'] = '---\nid: start\n---\n# Start', ['content/guide/02-next.md'] = '# Next',
    })
    t.eq({ 'content/01-intro.md', 'content/guide/01-first.md', 'content/guide/02-next.md' }, paths(result)); t.eq(2, #result.snapshot.trees)
    t.eq({ 'content/01-intro.md' }, paths(result, 2))
  end)
  t.test('Docusaurus autogenerated order/category metadata/index document', function()
    local result = parse('docusaurus', {
      ['sidebars.js'] = "export default {main:[{type:'autogenerated',dirName:'.'}]};",
      ['docs/01-intro.md'] = '# Intro', ['docs/02-guide/_category_.json'] = '{"label":"Tutorial","position":0}',
      ['docs/02-guide/index.md'] = '# Guide', ['docs/02-guide/a.md'] = '---\nsidebar_position: 2\n---\n# A', ['docs/02-guide/z.md'] = '---\nsidebar_position: 1\n---\n# Z',
    })
    t.eq({ 'docs/02-guide/index.md', 'docs/02-guide/z.md', 'docs/02-guide/a.md', 'docs/01-intro.md' }, paths(result))
    t.eq('Tutorial', result.snapshot.trees[1].items[1].title)
  end)
  t.test('Starlight explicit slug/automatic directory and order metadata without MDX execution', function()
    local result = parse('astro', {
      ['astro.config.mjs'] = "import {defineConfig} from 'astro/config';\nimport starlight from '@astrojs/starlight';\nexport default defineConfig({integrations:[starlight({title:'My docs',sidebar:['intro',{label:'Guides',autogenerate:{directory:'guides'}}]})]});",
      ['src/content/docs/intro.md'] = '---\ntitle: Introduction\n---\n# Intro',
      ['src/content/docs/guides/a.md'] = '---\ntitle: A\nsidebar:\n  order: 2\n---\n# A',
      ['src/content/docs/guides/z.mdx'] = '---\ntitle: Z\nslug: custom-z\nsidebar:\n  order: 1\n---\n<Component />',
      ['src/content/docs/guides/hidden.md'] = '---\ntitle: Hidden\nsidebar:\n  hidden: true\n---',
    })
    t.eq({ 'src/content/docs/intro.md', 'src/content/docs/guides/z.mdx', 'src/content/docs/guides/a.md' }, paths(result)); t.eq('ok', result.status)
    local plain = parse('astro', { ['astro.config.mjs'] = 'export default {}' }); t.eq('unsupported', plain.status)
  end)
  t.test('nearest project, YAML ambiguity and explicit selection', function()
    local root = fixture({ ['book.toml'] = '[book]', ['nested/mkdocs.yml'] = 'nav: []', ['nested/docs/a.md'] = '# A' })
    local detect = require('md-readable.navigation.detect')
    local result = detect.load(root .. '/nested/docs/a.md')
    t.eq('ambiguous', result.status); t.eq(2, #result.candidates); t.eq(root .. '/nested', result.candidates[1].root_dir)
    local explicit = detect.load(root .. '/nested/docs/a.md', { adapter = 'mkdocs' }); t.eq('ok', explicit.status)
    local summary_root = fixture({ ['SUMMARY.md'] = '# Summary' })
    t.eq(3, #detect.load(summary_root .. '/README.md').candidates)
  end)
  t.test('provider validates registered Lua and explicit JSON snapshots', function()
    local provider = require('md-readable.providers.navigation')
    local root = fixture({})
    local snapshot = { schemaVersion = 1, rootDir = root, adapterId = 'custom', orderOrigin = 'custom', trees = {}, diagnostics = {} }
    local unregister = provider.register('test', function() return snapshot end)
    t.eq('ok', provider.load('test', { root_dir = root }).status); unregister()
    t.eq('error', provider.load('test', { root_dir = root }).status)
    t.write(root .. '/nav.json', { vim.json.encode(snapshot) })
    t.eq('ok', provider.load('nav.json', { root_dir = root }).status)
    t.eq('error', provider.load(function() return {} end, { root_dir = root }).status)
  end)
  t.test('resolver distinguishes anchors, assets, external and missing without guessing rows', function()
    local root = fixture({ ['docs/日本語 name.md'] = '# Hello', ['docs/image.png'] = 'not actually an image' })
    local resolver = require('md-readable.navigation.resolver')
    local ctx = { path = root .. '/docs/日本語 name.md', root_dir = root, headings = { { id = 'hello', range = { start = { row = 0 } } }, { id = 'hello-1', range = { start = { row = 5 } } } } }
    t.eq('external', resolver.resolve('https://example.com/a?q=a#b', ctx).type)
    t.eq('asset', resolver.resolve('image.png', ctx).type)
    local target = resolver.resolve('%E6%97%A5%E6%9C%AC%E8%AA%9E%20name.md?q=a#hello-1', ctx)
    t.eq('document', target.type); t.eq(5, target.row); t.eq(ctx.path, target.path)
    t.eq('unresolved', resolver.resolve('#missing', ctx).type)
    t.eq('unresolved', resolver.resolve('missing.md', ctx).type)
    t.eq(ctx.path, resolver.resolve({ type = 'document', path = 'docs/日本語 name.md' }, ctx).path)
  end)
  t.test('static parser accepts semicolonless type import and literal require.resolve path without executing it', function()
    local value, errors = S.parse("import type {SidebarsConfig} from '@docusaurus/plugin-content-docs'\nconst sidebar: SidebarsConfig = {main: []}\nexport default sidebar")
    t.eq({}, errors); t.eq({}, value.main)
    local config, errors2 = S.extract("export default {docs:{path:'guide',sidebarPath:require.resolve('./custom.js')}}", 'docs', 'property')
    t.eq({}, errors2); t.eq('./custom.js', config.sidebarPath)
    local bad = S.parse("export default require.resolve(process.env.NAV)"); t.eq(nil, bad)
  end)
  t.test('unsupported syntax stays unsupported across YAML/TOML and adapter boundaries', function()
    local yamls = { 'nav: !include nav.yml', 'nav: &base []', 'nav: []\n---\nnav: []' }
    for _, text in ipairs(yamls) do
      local result = parse('mkdocs', { ['mkdocs.yml'] = text }); t.eq('unsupported', result.status); t.eq(nil, result.snapshot)
    end
    local toml = parse('zensical', { ['zensical.toml'] = '[project]\nnav = getenv("NAV")' }); t.eq('unsupported', toml.status)
    local doc = parse('docusaurus', { ['sidebars.js'] = 'export default {main: buildSidebar()}' }); t.eq('unsupported', doc.status)
    local astro = parse('astro', { ['astro.config.mjs'] = 'export default defineConfig({integrations:[starlight({sidebar: makeSidebar()})]})' }); t.eq('unsupported', astro.status)
  end)
  t.test('frontmatter metadata source errors and TOML blocks are explicit', function()
    local value, errors, finish = require('md-readable.parsers.frontmatter').parse({ '+++', 'title = "Title"', '+++', '# Body' }, 'doc.md')
    t.eq('Title', value.title); t.eq({}, errors); t.eq(3, finish)
    local bad, diagnostics = require('md-readable.parsers.frontmatter').parse({ '---', 'title: !ENV TITLE', '---' }, 'doc.md')
    t.eq(nil, bad); t.eq(1, diagnostics[1].source.row)
  end)
  t.test('GitBook single-space root and HonKit malformed JSON are not silently ignored', function()
    local result = parse('gitbook', { ['.gitbook.yaml'] = 'root: docs\nstructure:\n  summary: nav/SUMMARY.md', ['docs/nav/SUMMARY.md'] = '# Summary\n* [Intro](intro.md)', ['docs/intro.md'] = '# Intro' })
    t.eq({ 'docs/intro.md' }, paths(result))
    local bad = parse('honkit', { ['book.json'] = '{broken}', ['SUMMARY.md'] = '# Summary' })
    t.eq(nil, bad.snapshot); t.ok(#bad.diagnostics > 0)
  end)
  t.test('declared empty nav is successful and missing pages do not enter order', function()
    local empty = parse('mkdocs', { ['mkdocs.yml'] = 'nav: []' }); t.eq('ok', empty.status); t.eq({}, paths(empty))
    local missing = parse('zensical', { ['zensical.toml'] = '[project]\nnav = ["missing.md"]' }); t.eq('partial', missing.status); t.eq({}, paths(missing))
  end)
  t.test('Starlight configurable content root and custom loaders', function()
    local result = parse('astro', { ['astro.config.mjs'] = "export default {integrations:[starlight({title:'Docs',sidebar:['a']})]}", ['content/a.md'] = '---\ntitle: A\n---' }, { docs_dir = 'content' })
    t.eq({ 'content/a.md' }, paths(result))
    local loader = parse('astro', { ['astro.config.mjs'] = "starlight({title:'Docs'})", ['src/content.config.ts'] = 'export const collections = {docs: defineCollection({loader: remoteLoader()})}' })
    t.eq('unsupported', loader.status)
  end)
  t.test('model rejects bad target types and current path selection never invents occurrence', function()
    local result = parse('mkdocs', { ['mkdocs.yml'] = 'nav: []' })
    local snapshot = result.snapshot
    snapshot.trees[1].items = { { id = 'invalid', title = 'Invalid', children = {}, target = { type = 'document', path = '/absolute.md' } } }
    t.eq(false, require('md-readable.navigation.model').validate(snapshot))
    local index = Index.build(snapshot.trees[1]); t.eq(nil, Index.resolve_current('unlisted.md', { index = index }))
  end)
  t.test('unsaved config buffer content is preferred over disk', function()
    local root = fixture({ ['mkdocs.yml'] = 'nav: ["disk.md"]', ['docs/unsaved.md'] = '# Unsaved' })
    local buf = vim.fn.bufadd(root .. '/mkdocs.yml'); vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'nav: ["unsaved.md"]' })
    local result = require('md-readable.navigation.detect').load(root .. '/docs/unsaved.md', { root_dir = root, adapter = 'mkdocs' })
    t.eq({ 'docs/unsaved.md' }, paths(result))
    vim.api.nvim_buf_delete(buf, { force = true })
    t.eq({ 'nav: ["disk.md"]' }, vim.fn.readfile(root .. '/mkdocs.yml'))
  end)
  t.test('detection bound and explicit provider do not use unrelated ancestor projects', function()
    local root = fixture({ ['book.toml'] = '[book]', ['deep/docs/a.md'] = '# A' })
    local detect = require('md-readable.navigation.detect')
    t.eq('none', detect.load(root .. '/deep/docs/a.md', { max_depth = 1 }).status)
    local snapshot = { schemaVersion = 1, rootDir = root, adapterId = 'custom', orderOrigin = 'custom', trees = {}, diagnostics = {} }
    t.eq('custom', detect.load(root .. '/deep/docs/a.md', { provider = function() return snapshot end }).snapshot.adapterId)
  end)
end
