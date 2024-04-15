-- embedded styles are all styles between <style></style> tags
-- inside .html files
local M = {}
local j = require("plenary.job")
local u = require("html-css.utils.init")
local a = require("plenary.async")
local cmp = require("cmp")
local ts = vim.treesitter

---@type item[]
local classes = {}
local ids = {}
local links = {}

---@type string[]
local unique_class = {}
local unique_class_rule_set = {}
local unique_class_filename = {}
local unique_ids = {}
local unique_ids_rule_set = {}
local unique_ids_filename = {}

-- treesitter query for extracting css clasess
local htmldjango_extends_qs = [[
  (unpaired_statement
   (tag_name)@tag_name
   (string)@string)
]]

local style_qs = [[
  (style_element
    (raw_text)@style_content)
]]

local rule_set_qs = [[
  (rule_set) @rule
]]

local qs = [[
	(id_selector
		(id_name)@id_name)
	(class_selector
		(class_name)@class_name)
]]

local link_qs = [[
(element
    (start_tag
        (tag_name) @tag_name
        (attribute
            (attribute_name) @att_name (#eq? @att_name "href")
            (quoted_attribute_value
                (attribute_value) @att_val)))
    (#eq? @tag_name "link"))
]]

local function get_extends_template(data, htmldjango_extends_qs)
  -- Traverse the matched {% extends 'template.html' %}
  local tb_extend_links = {}
  local last_tag_name = ''
  -- use below query when current filetype is htmldjango
  if vim.bo.filetype == "htmldjango" then
    local parser = ts.get_string_parser(data, "htmldjango")
    local tree = parser:parse()[1]
    local root = tree:root()
    local query = ts.query.parse("htmldjango", htmldjango_extends_qs)
		
    for id, node in query:iter_captures(root, data, 0, -1) do
      if node:type() == "tag_name" then
        local tag_name = ts.get_node_text(node, data)
        last_tag_name = tag_name
      end
      if node:type() == "string" then
        if last_tag_name == "extends" then
          local extend_link = ts.get_node_text(node, data)
          extend_link = extend_link:gsub('^["\']', ''):gsub('["\']$', '')
          table.insert(tb_extend_links, extend_link)
        end
      end
    end
  end
  return tb_extend_links
end

local function extract_styles(data, style_query, root)
  local tb_styles = {}
  local styles = nil

  -- Traverse the matched <style> tags and extract the CSS content
  for id, node in style_query:iter_captures(root, data, 0, -1) do
    if node:type() == "raw_text" then
      local raw_text = ts.get_node_text(node, data)
      -- styles = raw_text
      table.insert(tb_styles, raw_text)
    end
  end
  styles = table.concat(tb_styles, "\n")
  return styles
end
local function extract_styles_from_html(data)
  local parser = ts.get_string_parser(data, "html")
  local tree = parser:parse()[1]
  local root = tree:root()
  local style_query = ts.query.parse("html", style_qs)

  local status, styles = pcall(extract_styles, data, style_query, root)
  if not status then
    -- failed to extract styles, return the original data
    return data
  end
  -- if styles is nil, return data
  return styles or data
end
local function extract_rule_sets(styles, rule_set_qs)
  local parser = ts.get_string_parser(styles, "css")
  local tree = parser:parse()[1]
  local root = tree:root()
  local query = ts.query.parse("css", rule_set_qs)
  local rule_sets = {}

  for id, node in query:iter_captures(root, 0, 0, -1) do
    local rule_text = ts.get_node_text(node, styles)
    table.insert(rule_sets, rule_text)
  end

  return rule_sets
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

local function read_file(file)
  local fd, err = io.open(file, "r")
  -- If failed to open file, return nil and error message
  if not fd then return nil, err end
  -- Try to read the file content
  local data = fd:read("*a")
  fd:close()
  return data
end

-- TODO: change name of the function to something better
M.read_html_files = a.wrap(function(cb)
  -- clean tables to avoid duplications
  links = {}
  classes = {}
  ids = {}

  local file, data = get_current_buffer_content_as_string()
  local file_name = u.get_file_name(file, "[^/]+$")
  local file_name = table.concat({ "", file_name }, " ")

  local tb_extend_links = get_extends_template(data, htmldjango_extends_qs)
  local files = {
    { file_name, data }
  }

  -- WARNING: new feature, need to test
  for _, v in ipairs(tb_extend_links) do
    table.insert(files, v)
  end

  unique_class = {}
  unique_class_rule_set = {}
  unique_class_filename = {}
  unique_ids = {}
  unique_ids_rule_set = {}
  unique_ids_filename = {}
  for _, file in ipairs(files) do
    local status = true
    local file_name
    local data
    if _ == 1 then
      file_name = file[1]
      data = file[2]
    else
      local current_file_path = vim.fn.expand('%:p:h')
      file = current_file_path .. "/" .. file
      file_name = u.get_file_name(file, "[^/]+$")
      status, data = pcall(read_file, file)
      if status then
        local success, parser_or_error = pcall(ts.get_string_parser, data, "html")
        if success then
          local parser = parser_or_error
          local tree = parser:parse()[1]
          local root = tree:root()

          local success, href_query_or_error = pcall(ts.query.parse, "html", link_qs)
          if success then
            local href_query = href_query_or_error
            -- run the query to find all href attributes
            for _, matches, _ in href_query:iter_matches(root, data, 0, -1) do
              for _, node in pairs(matches) do
                local nodeType = node:type()
                if nodeType == "attribute_value" or nodeType == "quoted_attribute_value" then
                  local href_value, get_node_text_error = ts.get_node_text(node, data)
                  if href_value then
                    -- if href_value:match(isRemote) then
                    table.insert(links, href_value)
                    -- end
                  else
                    -- Handle the error if ts.get_node_text failed
                    print("Error getting node text:", get_node_text_error)
                  end
                end
              end
            end
          else
            -- Handle the error if ts.query.parse failed
            print("Error parsing href query:", href_query_or_error)
          end
        else
          -- Handle the error if ts.get_string_parser failed
          print("Error creating parser:", parser_or_error)
        end
      end
    end
    if status then
      local success, styles = pcall(extract_styles_from_html, data)
      if success then
        local success, rule_sets = pcall(extract_rule_sets, styles, rule_set_qs)
        if success then
          for _, rule in ipairs(rule_sets) do
            local parser = ts.get_string_parser(rule, "css")
            local tree = parser:parse()[1]
            local root = tree:root()
            local query = ts.query.parse("css", qs)

            for _, matches, _ in query:iter_matches(root, rule, 0, 0, {}) do
              local last_chid_node = ''
              for _, node in pairs(matches) do
                if node:type() == "id_name" then
                  last_chid_node = node:type()
                  local id_name, get_node_text_error = ts.get_node_text(node, rule)
                  if id_name then
                    table.insert(unique_ids, id_name)
                    table.insert(unique_ids_rule_set, rule)
                    table.insert(unique_ids_filename, file_name)
                  else
                    -- Handle the error if ts.get_node_text failed
                    print("Error getting node text:", get_node_text_error)
                  end
                elseif node:type() == "class_name" then
                  last_chid_node = node:type()
                  local class_name, get_node_text_error = ts.get_node_text(node, rule)
                  if class_name then
                    table.insert(unique_class, class_name)
                    table.insert(unique_class_rule_set, rule)
                    table.insert(unique_class_filename, file_name)
                  else
                    -- Handle the error if ts.get_node_text failed
                    print("Error getting node text:", get_node_text_error)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- local unique_list = u.unique_list(unique_class)
  -- local unique_list, unique_block_list = u.unique_list_with_sync(unique_class, unique_class_rule_set)
  -- local unique_list, unique_block_list, unique_filename_list = u.unique_list_with_sync(unique_class,
  -- unique_class_rule_set, unique_class_filename)
  local unique_list, unique_block_list, unique_filename_list = unique_class, unique_class_rule_set, unique_class_filename
  for _, class in ipairs(unique_list) do
    file_name = unique_filename_list[_]
    table.insert(classes, {
      label = class,
      kind = cmp.lsp.CompletionItemKind.Enum,
      menu = file_name,
      file_path = file,
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
  -- unique_list, unique_block_list = u.unique_list_with_sync(unique_ids, unique_ids_rule_set)
  -- unique_list, unique_block_list, unique_filename_list = u.unique_list_with_sync(unique_ids, unique_ids_rule_set,
  --   unique_ids_filename)
  unique_list, unique_block_list, unique_filename_list = unique_ids, unique_ids_rule_set, unique_ids_filename
  for _, id in ipairs(unique_list) do
    file_name = unique_filename_list[_]
    table.insert(ids, {
      label = id,
      kind = cmp.lsp.CompletionItemKind.Enum,
      menu = file_name,
      file_path = file,
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
  links = u.unique_list(links)

  cb(classes, ids, links)
end, 1)

return M
