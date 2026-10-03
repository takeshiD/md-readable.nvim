local exports = {}
for _, name in ipairs({ "find_files", "live_grep", "grep_string", "buffers", "oldfiles" }) do
  exports[name] = function(opts) return require("md-readable.integrations.telescope").picker(name, opts) end
end
return require("telescope").register_extension({ exports = exports })
