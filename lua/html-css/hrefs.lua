local u = require("html-css.utils.init")
local ts = vim.treesitter
local isRemote = "^https?://"

local qs = [[
(element
    (start_tag
        (tag_name) @tag_name
        (attribute
            (attribute_name) @att_name (#eq? @att_name "href")
            (quoted_attribute_value
                (attribute_value) @att_val)))
    (#eq? @tag_name "link"))
]]

local M = { links = {} }

M.get_hrefs = function()
  M.links = {} -- clear the links

  -- get the current buffer content
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local data = table.concat(lines, "\n")

  -- use Treesitter to parse the current buffer content
  local parser = vim.treesitter.get_string_parser(data, "html")
  local tree = parser:parse()[1]
  local root = tree:root()
  local href_query = vim.treesitter.query.parse("html", qs)

  -- run the query to find all href attributes
  for _, matches, _ in href_query:iter_matches(root, bufnr, 0, #lines) do
    for _, node in pairs(matches) do
      local nodeType = node:type()
      if nodeType == "attribute_value" or nodeType == "quoted_attribute_value" then
        local href_value = vim.treesitter.get_node_text(node, bufnr)
        -- if href_value:match(isRemote) then
        table.insert(M.links, href_value)
        -- end
      end
    end
  end
  M.links = u.unique_list(M.links)

  return M.links
end

return M
