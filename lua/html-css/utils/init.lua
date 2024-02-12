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

---@param tbl1 table<number, any> The first table to process for uniqueness.
---@param tbl2 table<number, any> The second table to synchronize with the first table's unique list.
---@return table<number, any>, table<number, any> The first return value is the unique list derived from tbl1,
function M.unique_list_with_sync(tbl1, tbl2)
  local seen = {}
  local result_tbl1 = {}
  local result_tbl2 = {}

  for i, value in ipairs(tbl1) do
    if not seen[value] then
      seen[value] = true
      table.insert(result_tbl1, value)
      -- befacause tbl1 and tbl2 are in sync, we also insert elements from tbl2 accordingly
      -- this assumes that tbl2 is consistent with tbl1 in length and order
      if tbl2[i] then
        table.insert(result_tbl2, tbl2[i])
      end
    end
  end

  return result_tbl1, result_tbl2
end

return M
