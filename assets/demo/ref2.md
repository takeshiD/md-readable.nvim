# Ordering Tasks

[← Back to the index](./jump_link.md)

Once the tasks are loaded, the graph module decides the order. A task may run \
only after all of its dependencies have finished.

## Topological Sort

We walk the graph depth first and append a task after its dependencies. The \
result is a list in which every task comes after the tasks it depends on.

```lua
local function sort(tasks)
  local order, state = {}, {}
  local function visit(name)
    if state[name] == "done" then return end
    state[name] = "visiting"
    for _, dep in ipairs(tasks[name].deps or {}) do
      visit(dep)
    end
    state[name] = "done"
    order[#order + 1] = name
  end
  for name in pairs(tasks) do visit(name) end
  return order
end
```

## Cycle Detection

A cycle such as `build → test → build` has no valid order. We find it by \
noticing a task that is still marked `visiting` when we reach it again.

> [!WARNING]
> Report the whole cycle, not just the last edge. `build → test → build` is \
> far easier to fix than "cycle at build".

Previous: [Loading Task Files](./ref1.md) · Next: [Running Tasks](./ref3.md)
