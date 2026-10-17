# Deployment

`lumen build` writes a static site to `book/`. Upload that folder to \
any static host.

## GitHub Pages

```yaml
- run: lumen build
- uses: actions/upload-pages-artifact@v3
  with:
    path: book
```

## Checklist

- [x] Build passes without warnings
- [x] All internal links resolve
- [ ] Custom domain configured
