# Building a Tiny Task Runner in Lua

A walkthrough of a small, dependency-free task runner. It reads a task file, \
resolves dependencies, and runs each task once, in the right order.

> [!NOTE]
> This guide targets Lua 5.1 / LuaJIT, so it also runs inside Neovim.
> Every snippet is self-contained; paste it into `:lua` and try it.

## Overview

A task runner answers three questions: *what* should run, *in which order*, and \
*what happens when something fails*. We keep each answer in its own module so \
the pieces stay small and testable.

| Module      | Responsibility                    | Lines | Status    |
| ----------- | --------------------------------- | ----: | --------- |
| `loader`    | Read and validate the task file   |    48 | ✅ stable |
| `graph`     | Topological sort with cycle check |    62 | ✅ stable |
| `executor`  | Run tasks, collect results        |    95 | 🚧 beta   |
| `reporter`  | Pretty-print the summary          |    31 | 📝 draft  |

## Defining Tasks

Tasks are plain Lua tables. A task has a name, an optional list of \
dependencies, and a function that does the work.

```lua
local tasks = {
  fetch = { run = function() return "downloaded" end },
  build = { deps = { "fetch" }, run = function() return "compiled" end },
  test  = { deps = { "build" }, run = function() return "42 passed" end },
  ship  = { deps = { "build", "test" }, run = function() return "released" end },
}
```

Keeping tasks as data (not as classes) makes them easy to generate, filter, \
and print. The loader only checks that every `deps` entry refers to a known \
task.

### Validation Rules

- Every task **must** have a `run` function.
- `deps` is optional and defaults to an empty list.
- Unknown dependencies are reported with the task that mentions them.
- Names are case-sensitive: `Build` and `build` are different tasks.

## Resolving the Order

Dependencies form a directed graph. A depth-first search visits each task after \
all of its dependencies, which gives a valid execution order for free.

```lua
local function resolve(tasks)
  local order, state = {}, {}
  local function visit(name)
    if state[name] == "done" then return end
    assert(state[name] ~= "busy", "cycle at " .. name)
    state[name] = "busy"
    for _, dep in ipairs(tasks[name].deps or {}) do
      visit(dep)
    end
    state[name] = "done"
    table.insert(order, name)
  end
  for name in pairs(tasks) do visit(name) end
  return order
end
```

### Detecting Cycles

The `busy` marker is the whole trick. If we meet a task that is still being \
visited, we have walked in a circle. The assertion message names the task where \
the cycle closed, which is usually enough to find the mistake.

## Running Tasks

The executor walks the resolved order and calls each `run` function inside \
`pcall`, so one failing task cannot crash the whole run.

```lua
local function execute(tasks, order)
  local results = {}
  for _, name in ipairs(order) do
    local ok, value = pcall(tasks[name].run)
    results[#results + 1] = { name = name, ok = ok, value = value }
    if not ok then break end
  end
  return results
end
```

Stopping at the first failure is a deliberate choice: later tasks usually \
depend on earlier ones, so their output would be meaningless anyway.

### Parallel Execution

Independent tasks could run at the same time. With `vim.uv` this means one \
process handle per task and a small scheduler that starts a task as soon as \
all of its dependencies have finished. That is a topic for a follow-up guide.

## Reporting

A good summary fits on one screen. We print one line per task with a status \
mark, then a final line with the totals.

1. Collect the results from the executor.
2. Pad the names to the longest one.
3. Print `✓` for success and `✗` for failure.
4. Finish with `n passed, m failed`.

- [x] Plain text output
- [x] Colored output
- [ ] JSON output for CI
- [ ] Timing per task

## Next Steps

You now have a complete, if tiny, task runner. From here you could add \
caching[^cache], watch mode, or a command line front end. See the \
[Lua reference manual](https://www.lua.org/manual/5.1/) for the details of \
`pcall` and [error handling](#running-tasks).

[^cache]: Hash the inputs of each task and skip it when the hash is unchanged.
