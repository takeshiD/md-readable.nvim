local M = {}
function M.validate(snapshot)
  local diagnostics = {}
  local function err(code, message, id)
    diagnostics[#diagnostics + 1] = { severity = "error", code = code, message = message, nodeId = id }
  end
  local function str(v)
    return type(v) == "string" and v ~= ""
  end
  local function array(v)
    return type(v) == "table" and vim.islist(v)
  end
  if type(snapshot) ~= "table" then
    err("snapshot-type", "Snapshot must be a table")
    return false, diagnostics
  end
  if snapshot.schemaVersion ~= 1 then
    err("snapshot-version", "Only schemaVersion 1 is supported")
  end
  if not str(snapshot.rootDir) or not snapshot.rootDir:match("^/") then
    err("snapshot-root", "rootDir must be absolute")
  end
  if not str(snapshot.adapterId) then
    err("snapshot-adapter", "adapterId is required")
  end
  if not vim.tbl_contains({ "declared", "generated", "inferred", "custom" }, snapshot.orderOrigin) then
    err("snapshot-order", "Invalid orderOrigin")
  end
  if not array(snapshot.diagnostics) then
    err("snapshot-diagnostics", "diagnostics must be an array")
  end
  if not array(snapshot.trees) then
    err("snapshot-trees", "trees must be an array")
    return false, diagnostics
  end
  local tree_ids = {}
  for _, tree in ipairs(snapshot.trees) do
    if type(tree) ~= "table" or not str(tree.id) then
      err("tree-id", "Tree needs an id")
    else
      if tree_ids[tree.id] then
        err("duplicate-tree", "Duplicate tree id: " .. tree.id)
      end
      tree_ids[tree.id] = true
      local ids, active = {}, {}
      local function visit(nodes)
        if not array(nodes) then
          err("node-children", "items and children must be arrays")
          return
        end
        for _, node in ipairs(nodes) do
          if type(node) ~= "table" then
            err("node-type", "Node must be a table")
          elseif active[node] then
            err("node-cycle", "Cycle in navigation tree", node.id)
          else
            active[node] = true
            if not str(node.id) then
              err("node-id", "Node id is required")
            elseif ids[node.id] then
              err("duplicate-id", "Duplicate node id: " .. node.id, node.id)
            else
              ids[node.id] = true
            end
            if type(node.title) ~= "string" then
              err("node-title", "Node title must be a string", node.id)
            end
            local target = node.target
            if target ~= nil then
              if type(target) ~= "table" then
                err("target-type", "Invalid target", node.id)
              elseif target.type == "document" then
                if
                  not str(target.path)
                  or target.path:match("^/")
                  or target.path:find("[\\?#]")
                  or target.path:match("^%a+:")
                then
                  err("target-path", "Document path must be normalized and root-relative", node.id)
                end
                if target.anchor ~= nil and type(target.anchor) ~= "string" then
                  err("target-anchor", "Anchor must be a string", node.id)
                end
              elseif target.type == "external" then
                if not str(target.url) then
                  err("target-url", "External URL is required", node.id)
                end
              elseif target.type == "unavailable" then
                if not str(target.reason) or type(target.raw) ~= "string" then
                  err("target-unavailable", "Unavailable target requires raw and reason", node.id)
                end
              else
                err("target-type", "Unknown navigation target type", node.id)
              end
            end
            visit(node.children)
            active[node] = nil
          end
        end
      end
      visit(tree.items)
    end
  end
  return #diagnostics == 0, diagnostics
end
return M
