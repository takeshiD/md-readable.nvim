# Themes

Lumen comes with three built-in themes.

| Theme   | Background | Accent  | Best for          |
| ------- | ---------- | ------- | ----------------- |
| `paper` | light      | blue    | long-form reading |
| `ink`   | dark       | amber   | night owls        |
| `mono`  | light      | black   | printing          |

Set the theme in `lumen.toml`:

```toml
[output.html]
theme = "ink"
```

## Custom CSS

Put extra rules in `theme/custom.css`. They are loaded after the \
built-in theme, so they win when both set the same property.
