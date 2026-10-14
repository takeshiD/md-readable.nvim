# Projects

A project is a folder with a `lumen.toml` file. Pages live in `src/`, \
and `SUMMARY.md` decides the order in which readers see them.

## Nesting pages

Indent a list item to make a page a child of the item above it. \
Children are shown below their parent in the sidebar.

```markdown
- [Guide](guide.md)
    - [Install](guide/install.md)
    - [Usage](guide/usage.md)
```

## Draft pages

A link with an empty target creates a draft chapter. \
Drafts appear in the table of contents but have no page yet.
