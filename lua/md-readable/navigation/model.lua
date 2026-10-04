local M = {}
-- NavigationSnapshot (design document camelCase fields). Paths are root-relative unless noted.
---@alias MdReadableNavOrderOrigin "declared"|"generated"|"inferred"|"custom"
---@alias MdReadableNavSeverity "error"|"warning"|"info"
---@alias MdReadableNavStatus "ok"|"partial"|"error"|"unsupported"|"ambiguous"|"none"
---@class MdReadableNavSource
---@field path string
---@field row? integer 0-based; absent for a whole file
---@field byteColumn? integer 0-based byte column
---@class MdReadableNavDiagnostic
---@field severity MdReadableNavSeverity
---@field code string
---@field message string
---@field source? MdReadableNavSource
---@field nodeId? string
---@class MdReadableNavDocumentTarget
---@field type "document"
---@field path string Normalized root-relative path
---@field anchor? string
---@class MdReadableNavExternalTarget
---@field type "external"
---@field url string
---@class MdReadableNavUnavailableTarget
---@field type "unavailable"
---@field raw string Original spelling
---@field reason string
---@alias MdReadableNavTarget MdReadableNavDocumentTarget|MdReadableNavExternalTarget|MdReadableNavUnavailableTarget
---@class MdReadableNavNode
---@field id string
---@field title string
---@field target? MdReadableNavTarget Absent for plain groups
---@field children MdReadableNavNode[]
---@field source? MdReadableNavSource
---@field position? number Adapter sort position (math.huge when unset)
---@field sort_key? string Adapter sort tie-breaker
---@class MdReadableNavTree
---@field id string
---@field title string
---@field items MdReadableNavNode[]
---@class MdReadableNavSnapshot
---@field schemaVersion 1
---@field rootDir string Absolute
---@field adapterId string
---@field orderOrigin MdReadableNavOrderOrigin
---@field trees MdReadableNavTree[]
---@field diagnostics MdReadableNavDiagnostic[]
---@class MdReadableNavResult
---@field status MdReadableNavStatus
---@field snapshot? MdReadableNavSnapshot
---@field diagnostics MdReadableNavDiagnostic[]
---@field dependencies? string[] Absolute paths that invalidate the snapshot
---@field candidates? MdReadableNavCandidate[]
-- Reader returns text or lines; nil when unavailable.
---@alias MdReadableNavReader fun(path:string):(string|string[]|nil)
---@alias MdReadableNavProvider string|table|MdReadableNavProviderCallback
-- User `adapters` options.
---@class MdReadableNavOptions
---@field adapter? string Force an adapter id
---@field root_dir? string Absolute project root (disables upward search)
---@field config_path? string Root-relative config file
---@field provider? MdReadableNavProvider
---@field read? MdReadableNavReader
---@field list? fun(dir:string):string[] Absolute paths of files under dir
---@field max_depth? integer Upward search limit
---@field stop_dir? string
---@field docs_dir? string
---@field sidebar_path? string|false
---@class MdReadableNavContext: MdReadableNavOptions
---@field root_dir string
---@field path string Absolute path of the current document
---@class MdReadableNavAdapter
---@field parse fun(ctx:MdReadableNavContext):MdReadableNavResult
---@param snapshot any
---@return boolean valid
---@return MdReadableNavDiagnostic[] diagnostics
function M.validate(snapshot)
  local diagnostics = {}
  ---@param code string
  ---@param message string
  ---@param id? string
  local function err(code, message, id)
    diagnostics[#diagnostics + 1] = { severity = "error", code = code, message = message, nodeId = id }
  end
  ---@param v any
  ---@return boolean
  local function str(v)
    return type(v) == "string" and v ~= ""
  end
  ---@param v any
  ---@return boolean
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
      ---@param nodes any
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
