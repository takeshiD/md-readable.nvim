local C = require("md-readable.adapters.common")
local Registry = require("md-readable.adapters.registry")
local M = {}
---@class MdReadableNavCandidate
---@field root_dir string Absolute
---@field adapter_id string
---@field config_path? string Root-relative config file
---@field evidence? string[]
---@field priority? integer Higher is nearer to the start directory
---@param path string Absolute
---@param opts MdReadableNavOptions
---@return boolean
local function exists(path, opts)
  if opts.read then
    return opts.read(path) ~= nil
  end
  local buf = vim.fn.bufnr(path)
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then
    return true
  end
  return vim.fn.filereadable(path) == 1
end
---@param path string File or directory
---@param opts? MdReadableNavOptions
---@return MdReadableNavCandidate[]
function M.candidates(path, opts)
  opts = opts or {}
  local start = opts.root_dir or (vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path))
  local dir, steps = vim.fs.normalize(vim.fn.fnamemodify(start, ":p")):gsub("/$", ""), 0
  local summary_fallback
  if dir == "" then
    dir = "/"
  end
  while dir and steps < (opts.max_depth or 32) do
    local candidates = {}
    for _, entry in ipairs(Registry.entries) do
      if not opts.adapter or opts.adapter == entry.id then
        for _, name in ipairs(entry.files) do
          local config = C.join(dir, name)
          if exists(config, opts) then
            candidates[#candidates + 1] =
              { root_dir = dir, adapter_id = entry.id, config_path = name, evidence = { name }, priority = 100 - steps }
            break
          end
        end
      end
    end
    -- A SUMMARY in the source folder is not a competing project root when its
    -- parent's book.toml (or another explicit config) identifies the project.
    -- Retain it only if no actual project marker is found within the boundary.
    if #candidates > 0 then
      return candidates
    end
    if exists(C.join(dir, "SUMMARY.md"), opts) then
      for _, id in ipairs({ "mdbook", "honkit", "gitbook" }) do
        if not opts.adapter or id == opts.adapter then
          candidates[#candidates + 1] = {
            root_dir = dir,
            adapter_id = id,
            evidence = { "SUMMARY.md alone does not identify its generator" },
            priority = 10,
          }
        end
      end
      summary_fallback = summary_fallback or candidates
    end
    if opts.root_dir or opts.stop_dir == dir or dir == "/" then
      break
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
    steps = steps + 1
  end
  return summary_fallback or {}
end
---@param path string Absolute path of the current document
---@param opts? MdReadableNavOptions
---@return MdReadableNavResult
function M.load(path, opts)
  opts = opts or {}
  if opts.provider then
    local ctx = vim.tbl_extend("force", opts, { root_dir = opts.root_dir or vim.fs.dirname(path), path = path })
    return require("md-readable.providers.navigation").load(opts.provider, ctx)
  end
  local candidates = M.candidates(path, opts)
  local chosen
  if opts.adapter and opts.root_dir then
    chosen = candidates[1] or { root_dir = opts.root_dir, adapter_id = opts.adapter, config_path = opts.config_path }
  elseif #candidates == 1 then
    chosen = candidates[1]
  elseif #candidates > 1 then
    return {
      status = "ambiguous",
      candidates = candidates,
      diagnostics = {
        {
          severity = "info",
          code = "ambiguous-project",
          message = "Choose an adapter: project files have multiple valid interpretations",
        },
      },
    }
  else
    return { status = "none", candidates = {}, diagnostics = {} }
  end
  local adapter = Registry.get(chosen.adapter_id)
  if not adapter then
    return {
      status = "error",
      diagnostics = {
        { severity = "error", code = "unknown-adapter", message = "Unknown adapter: " .. tostring(chosen.adapter_id) },
      },
    }
  end
  local ctx = vim.tbl_extend(
    "force",
    opts,
    { root_dir = chosen.root_dir, config_path = opts.config_path or chosen.config_path, path = path }
  )
  local ok, result = pcall(adapter.parse, ctx)
  if not ok then
    return {
      status = "error",
      diagnostics = { { severity = "error", code = "adapter-error", message = tostring(result) } },
    }
  end
  result.candidates = candidates
  return result
end
return M
