# Running Tasks

[← Back to the index](./jump_link.md)

The executor takes the sorted list and runs each task exactly once. Results are \
collected in a table keyed by task name, so later tasks can read the output of \
earlier ones.

## Execution

```lua
local function execute(tasks, order)
  local results = {}
  for _, name in ipairs(order) do
    local ok, value = pcall(tasks[name].run, results)
    results[name] = { ok = ok, value = value }
    if not ok then
      return results, name
    end
  end
  return results
end
```

## Handling Failures

When a task fails, every task that depends on it is skipped. Tasks on other \
branches of the graph could still run, but stopping early keeps the output \
short and the first error easy to find.

- ✅ `fetch` finished
- ❌ `build` failed
- ⏭️ `test` skipped (depends on `build`)

## The Report

The reporter prints one line per task and a summary at the end, such as \
`2 passed, 1 failed, 1 skipped`.

Previous: [Ordering Tasks](./ref2.md)
