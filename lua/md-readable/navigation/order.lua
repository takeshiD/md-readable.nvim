local M = {}
function M.reading_order(tree, root_dir, available)
  available = available or function(path) return vim.fn.filereadable(vim.fs.joinpath(root_dir or '.', path)) == 1 end
  local out = {}
  for _, node in ipairs(require('md-readable.navigation.index').build(tree).order) do
    if node.target and node.target.type == 'document' and available(node.target.path, node) then out[#out + 1] = node end
  end
  return out
end
function M.adjacent(tree, node_id, direction, root_dir, available)
  local order = M.reading_order(tree, root_dir, available)
  local delta = (direction == 'previous' or direction == 'prev' or direction == -1) and -1 or 1
  for i, node in ipairs(order) do if node.id == node_id then return order[i + delta] end end
end
return M
