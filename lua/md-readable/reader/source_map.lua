local M = {}
local Map = {}
Map.__index = Map
local function clamp(n, lo, hi)
  return math.max(lo, math.min(n, hi))
end
function M.new(source_lines, rendered)
  local self = setmetatable({ source = source_lines, rendered = rendered, display = {}, original = {}, rows = {} }, Map)
  for _, segment in ipairs(rendered.segments or {}) do
    self.display[segment.row] = self.display[segment.row] or {}
    table.insert(self.display[segment.row], segment)
    self.original[segment.source_row] = self.original[segment.source_row] or {}
    table.insert(self.original[segment.source_row], segment)
  end
  for display, original in pairs(rendered.row_map or {}) do
    if original ~= nil and not self.rows[original] then
      self.rows[original] = display - 1
    end
  end
  for _, segments in pairs(self.display) do
    table.sort(segments, function(a, b)
      return a.start_col < b.start_col
    end)
  end
  return self
end
function Map:to_source(row, col)
  local segments = self.display[row] or {}
  local best
  for _, s in ipairs(segments) do
    best = s
    if col < s.end_col then
      return s.source_row, clamp(s.source_start + math.max(0, col - s.start_col), s.source_start, s.source_end)
    end
  end
  if best then
    return best.source_row, best.source_end
  end
  local source_row = self.rendered.row_map[row + 1]
  if source_row ~= nil then
    return source_row, 0
  end
  for distance = 1, #self.rendered.lines do
    for _, index in ipairs({ row + 1 - distance, row + 1 + distance }) do
      source_row = self.rendered.row_map[index]
      if source_row ~= nil then
        return source_row, 0
      end
    end
  end
  return 0, 0
end
function Map:to_display(row, col)
  col = col or 0
  local candidates = self.original[row] or {}
  for _, s in ipairs(candidates) do
    if col >= s.source_start and col < s.source_end then
      return s.row, clamp(s.start_col + col - s.source_start, s.start_col, math.max(s.start_col, s.end_col - 1))
    end
  end
  for _, s in ipairs(candidates) do
    if s.full_start and col >= s.full_start and col < s.full_end then
      return s.row, s.start_col
    end
  end
  if candidates[1] then
    local last = candidates[#candidates]
    if col >= last.source_end then
      return last.row, last.end_col
    end
    return candidates[1].row, candidates[1].start_col
  end
  if self.rows[row] then
    return self.rows[row], 0
  end
  local best, distance
  for source, display in pairs(self.rows) do
    if not distance or math.abs(source - row) < distance then
      best, distance = display, math.abs(source - row)
    end
  end
  return best or 0, 0
end
function Map:copy(sr, sc, er, ec, mode, columns)
  if er < sr or (er == sr and ec < sc) then
    sr, sc, er, ec = er, ec, sr, sc
  end
  local ranges = {}
  local last = er - (ec == 0 and er > sr and mode ~= "block" and 1 or 0)
  local groups = {}
  local function key(s)
    return s.source_row .. ":" .. s.full_start .. ":" .. s.full_end
  end
  for _, s in ipairs(self.rendered.segments or {}) do
    if s.full_start and s.kind ~= "omission" then
      local k = key(s)
      groups[k] = groups[k] or { total = 0, selected = 0, complete = true }
      if s.node_complete == false then
        groups[k].complete = false
      end
      groups[k].total = groups[k].total + s.end_col - s.start_col
      if s.row >= sr and s.row <= last then
        local lo = columns and columns[s.row] and columns[s.row][1] or ((s.row == sr or mode == "block") and sc or 0)
        local hi = columns and columns[s.row] and columns[s.row][2]
          or ((s.row == er or mode == "block") and ec or math.huge)
        groups[k].selected = groups[k].selected + math.max(0, math.min(hi, s.end_col) - math.max(lo, s.start_col))
      end
    end
  end
  local function add(row, first, final)
    if final <= first then
      return
    end
    local entry = ranges[row]
    if entry then
      entry[1], entry[2] = math.min(entry[1], first), math.max(entry[2], final)
    else
      ranges[row] = { first, final }
    end
  end
  for row = sr, last do
    if mode == "line" then
      local source_rows = vim.deepcopy((self.rendered.source_rows or {})[row + 1] or {})
      if #source_rows == 0 then
        for _, segment in ipairs(self.display[row] or {}) do
          source_rows[#source_rows + 1] = segment.source_row
        end
      end
      if #source_rows == 0 then
        local source_row = self.rendered.row_map[row + 1]
        if source_row ~= nil and self.source[source_row + 1] == "" then
          source_rows = { source_row }
        end
      end
      for _, source_row in ipairs(source_rows) do
        if #(self.display[row] or {}) > 0 or self.source[source_row + 1] == "" then
          ranges[source_row] = { 0, #(self.source[source_row + 1] or "") }
        end
      end
    else
      local lo = columns and columns[row] and columns[row][1] or ((row == sr or mode == "block") and sc or 0)
      local hi = columns and columns[row] and columns[row][2] or ((row == er or mode == "block") and ec or math.huge)
      for _, s in ipairs(self.display[row] or {}) do
        local a, b = math.max(lo, s.start_col), math.min(hi, s.end_col)
        if b > a then
          if
            s.kind == "omission"
            or (s.full_start and groups[key(s)].complete and groups[key(s)].selected == groups[key(s)].total)
          then
            add(s.source_row, s.full_start or s.source_start, s.full_end or s.source_end)
          elseif a == s.start_col and b == s.end_col then
            add(s.source_row, s.source_start, s.source_end)
          else
            add(
              s.source_row,
              clamp(s.source_start + a - s.start_col, s.source_start, s.source_end),
              clamp(s.source_start + b - s.start_col, s.source_start, s.source_end)
            )
          end
        end
      end
    end
  end
  local keys = vim.tbl_keys(ranges)
  table.sort(keys)
  if #keys == 0 then
    return nil
  end
  local lines = {}
  for _, row in ipairs(keys) do
    local range = ranges[row]
    lines[#lines + 1] = (self.source[row + 1] or ""):sub(range[1] + 1, range[2])
  end
  local regtype = mode == "line" and "V" or "v"
  if mode == "block" then
    local width = 1
    for _, line in ipairs(lines) do
      width = math.max(width, vim.fn.strdisplaywidth(line))
    end
    regtype = "\22" .. width
  end
  return table.concat(lines, "\n"), regtype
end
return M
