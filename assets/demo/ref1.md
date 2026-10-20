# Loading Task Files

[← Back to the index](./jump_link.md)

The loader turns a task file into a plain Lua table. A task file is just a Lua \
chunk that returns a table, so loading it is a matter of `loadfile` plus a few \
checks.

## Reading the File

```lua
local function load(path)
  local chunk, err = loadfile(path)
  if not chunk then
    return nil, err
  end
  return chunk()
end
```

The chunk runs in an empty environment, so a task file cannot reach globals \
by accident.

## Validation

Every task must have a `run` function. Dependencies, when present, must be a \
list of task names that exist in the same file.

| Field  | Type       | Required |
| ------ | ---------- | :------: |
| `run`  | `function` |    ✅    |
| `deps` | `string[]` |    —     |
| `desc` | `string`   |    —     |

> [!TIP]
> Validate everything before running anything. A typo in a dependency name \
> should fail fast, not halfway through a build.

Next: [Ordering Tasks](./ref2.md)
