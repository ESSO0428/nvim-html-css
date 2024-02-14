local M = {}

---@return string
function M.get_file_name(file, pattern)
  -- "[^/]+%.%w+$"  -- from url
  -- "[^/]+$" -- from local file
  local fileName = file:match(pattern)
  return fileName
end

---@return table<string[]>
function M.unique_list(tbl)
  local seen = {}
  local result = {}

  for _, value in ipairs(tbl) do
    if not seen[value] then
      table.insert(result, value)
      seen[value] = true
    end
  end

  return result
end

--- Returns unique elements from the first table and corresponding elements from subsequent tables.
-- @param ... Variable number of tables. The first table is used to determine uniqueness,
--            and subsequent tables must be synchronized with the first table in length and order.
-- @return Multiple tables. The first returned table contains unique elements from the first input table,
--         and each subsequent table contains elements corresponding to the unique elements' positions
--         from their respective input tables.
function M.unique_list_with_sync(...)
  local seen = {}
  local result_tbls = {}
  local args = { ... }

  -- Initialize result tables for each input table
  for i = 1, #args do
    result_tbls[i] = {}
  end

  for i, value in ipairs(args[1]) do
    if not seen[value] then
      seen[value] = true
      -- Insert unique value from the first table
      table.insert(result_tbls[1], value)
      -- Insert corresponding elements from other tables
      for j = 2, #args do
        if args[j][i] then
          table.insert(result_tbls[j], args[j][i])
        end
      end
    end
  end

  return table.unpack(result_tbls)
end

return M
