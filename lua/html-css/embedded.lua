-- embedded styles are all styles between <style></style> tags
-- inside .html files
local M = {
  links = {},
}
local j = require("plenary.job")
local u = require("html-css.utils.init")
local a = require("plenary.async")
local cmp = require("cmp")
local ts = vim.treesitter

---@type item[]
local classes = {}
local ids = {}

---@type string[]
local unique_class = {}
local unique_class_rule_set = {}
local unique_ids = {}
local unique_ids_rule_set = {}

-- treesitter query for extracting css clasess
local style_qs = [[
  (style_element
    (raw_text)@style_content)
]]

local qs = [[
  (rule_set
    (selectors
      (id_selector
        (id_name)@id_name)))@id_block
  (rule_set
    (selectors
      (class_selector
        (class_name)@class_name)))@class_block
]]

local function extract_styles(data, style_query, root)
  local styles = nil -- 初始化styles为nil，这样可以在没有找到匹配时返回nil
  -- 遍历匹配的<style>标签，提取CSS内容
  for id, node in style_query:iter_captures(root, data, 0, -1) do
    if node:type() == "raw_text" then
      local raw_text = ts.get_node_text(node, data)
      styles = raw_text
      break -- 假设我们只关心第一个匹配的<style>标签
    end
  end
  return styles
end
local function extract_styles_from_html(data)
  local parser = ts.get_string_parser(data, "html")
  local tree = parser:parse()[1]
  local root = tree:root()
  local style_query = ts.query.parse("html", style_qs)

  local status, styles = pcall(extract_styles, data, style_query, root)
  if not status then
    return data -- 失败时返回原始data
  end

  return styles or data -- 如果styles为nil，则返回data
end

local function deindent(text)
  local indent = string.match(text, '^%s*')
  if not indent then
    return text
  end
  return string.gsub(string.gsub(text, '^' .. indent, ''), '\n' .. indent, '\n')
end

local function get_current_buffer_content_as_string()
  -- get current buffer number
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  -- get all lines of current buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- concat all lines into a string, join
  local data = table.concat(lines, "\n")
  return file, data
end

-- TODO change name of the function to something better
M.read_html_files = a.wrap(function(cb)
  -- clean tables to avoid duplications
  classes = {}
  ids = {}

  local file, data = get_current_buffer_content_as_string()
  local file_name = u.get_file_name(file, "[^/]+$")
  file_name = table.concat({ "", file_name }, " ")
  local styles = extract_styles_from_html(data)
  unique_class = {}
  unique_class_rule_set = {}
  unique_ids = {}
  unique_ids_rule_set = {}

  local parser = ts.get_string_parser(styles, "css")
  local tree = parser:parse()[1]
  local root = tree:root()
  local query = ts.query.parse("css", qs)

  for _, matches, _ in query:iter_matches(root, styles, 0, 0, {}) do
    local last_chid_node = ''
    for _, node in pairs(matches) do
      if node:type() == "id_name" then
        last_chid_node = node:type()
        local id_name = ts.get_node_text(node, styles)
        table.insert(unique_ids, id_name)
      elseif node:type() == "class_name" then
        last_chid_node = node:type()
        local class_name = ts.get_node_text(node, styles)
        table.insert(unique_class, class_name)
      end
      if node:type() == "rule_set" then
        if last_chid_node == "id_name" then
          local id_block = ts.get_node_text(node, styles)
          table.insert(unique_ids_rule_set, id_block)
        elseif last_chid_node == "class_name" then
          local class_block = ts.get_node_text(node, styles)
          table.insert(unique_class_rule_set, class_block)
        end
      end
    end
  end
  -- local unique_list = u.unique_list(unique_class)
  local unique_list, unique_block_list = u.unique_list_with_sync(unique_class, unique_class_rule_set)
  for _, class in ipairs(unique_list) do
    table.insert(classes, {
      label = class,
      kind = cmp.lsp.CompletionItemKind.Enum,
      menu = file_name,
      documentation = {
        kind = 'markdown',
        value = table.concat({
          '```' .. 'css',
          deindent(unique_block_list[_]),
          '```'
        }, '\n'),
      }
    })
  end
  -- local unique_ids_list = u.unique_list(unique_ids)
  unique_list, unique_block_list = u.unique_list_with_sync(unique_ids, unique_ids_rule_set)
  for _, id in ipairs(unique_list) do
    table.insert(ids, {
      label = id,
      kind = cmp.lsp.CompletionItemKind.Enum,
      menu = file_name,
      documentation = {
        kind = 'markdown',
        value = table.concat({
          '```' .. 'css',
          deindent(unique_block_list[_]),
          '```'
        }, '\n'),
      }
    })
  end
  cb(classes, ids)
end, 1)

return M
