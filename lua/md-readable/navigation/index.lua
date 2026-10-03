local M = {}
function M.build(tree)
  local out, visited = { by_id = {}, by_path = {}, parent = {}, order = {} }, {}
  local function visit(nodes, parent)
    for _, node in ipairs(nodes or {}) do
      if not visited[node] then
        visited[node] = true
        out.by_id[node.id] = node; out.parent[node.id] = parent
        out.order[#out.order + 1] = node
        if node.target and node.target.type == 'document' then
          local path = node.target.path
          out.by_path[path] = out.by_path[path] or {}
          table.insert(out.by_path[path], node)
        end
        visit(node.children, node.id)
      end
    end
  end
  visit(tree.items)
  return out
end
function M.resolve_current(path, context)
  context = context or {}
  local index = context.index or M.build(context.tree)
  local nodes = index.by_path[path] or {}
  local wanted = context.selected_id or (context.history and context.history[path])
  for _, node in ipairs(nodes) do if node.id == wanted then return node end end
  return nodes[1]
end
function M.breadcrumbs(index, node_id)
  local out, seen = {}, {}
  while node_id and index.by_id[node_id] and not seen[node_id] do
    seen[node_id] = true; table.insert(out, 1, index.by_id[node_id]); node_id = index.parent[node_id]
  end
  return out
end
return M
