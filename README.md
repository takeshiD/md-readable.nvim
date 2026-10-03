# md-readable.nvim

[日本語版](README_ja.md)

A Neovim plugin specialized in making Markdown easy to read.
It provides the following features.

- Appearance
    - Markdown syntax highlighting
    - Table rendering
    - Code blocks
    - Color theme switching
    - Truncated display of long text in tables / URLs
    - Distinct icons for local links and external links
- Navigation
    - Minimap
    - Heading tree
    - Focus Mode
    - Table of contents and previous/next navigation for major SSGs
        - Supported SSGs: mdBook, Docusaurus, MkDocs, Astro, Honkit, GitBook
- Formatting
    - Table formatting
- Contents
    - Image display (png, jpg, svg, webp, etc.)
    - Mermaid diagram rendering

Some writing support is also included.
- Writing
    - Cursor synchronization between the Read Buffer and the Write Buffer

# Requirements
- Neovim >= 0.12
- (Optional) Image display: tested on WezTerm and Ghostty
- (Optional) Mermaid: mermaid-cli, Mermaid

# License
MIT
