# md-readable.nvim

[日本語版](README_ja.md)

A Neovim plugin specialized in making Markdown easy to read.
The following features are required implementation targets. The plugin is currently unimplemented; requirements are being refined in [the design document](md-readable_design.md).

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
        - Required SSG targets: mdBook, Docusaurus, MkDocs, Zensical, Astro, HonKit, GitBook
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

The reference plugins listed in AGENTS.md are implementation references, not required dependencies. Their required functionality will be implemented within this plugin.

See the [final specification draft](docs/final-spec-review.md) and [parallel implementation plan](docs/implementation-issues.md).

# Requirements
- Neovim >= 0.12
- (Optional) Image display: WezTerm and Ghostty are target environments; verification is pending implementation
- (Optional) Mermaid: mermaid-cli, Mermaid

# License
MIT
