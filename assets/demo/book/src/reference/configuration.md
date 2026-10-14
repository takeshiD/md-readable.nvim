# Configuration

All settings live in `lumen.toml` at the project root.

```toml
[book]
title = "My Notes"
src = "src"

[output.html]
theme = "paper"
search = true
```

## Keys

| Key                  | Default   | Meaning                    |
| -------------------- | --------- | -------------------------- |
| `book.title`         | folder    | Site title                 |
| `book.src`           | `"src"`   | Directory with the pages   |
| `output.html.theme`  | `"paper"` | One of the built-in themes |
| `output.html.search` | `true`    | Build the search index     |
