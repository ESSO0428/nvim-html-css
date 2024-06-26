local M = {}
local a = require("plenary.async")
local u = require("html-css.utils.init")
local j = require("plenary.job")
local cmp = require("cmp")
local ts = vim.treesitter

---@type table<item>[]
local classes = {}
local ids = {}

-- treesitter query for extracting css clasess
local rule_set_qs = [[
  (rule_set) @rule
]]

local qs = [[
	(id_selector
		(id_name)@id_name)
	(class_selector
		(class_name)@class_name)
]]


local function extract_rule_sets(data, rule_set_qs)
  local parser = ts.get_string_parser(data, "css")
  local tree = parser:parse()[1]
  local root = tree:root()
  local query = ts.query.parse("css", rule_set_qs)
  local rule_sets = {}

  for id, node in query:iter_captures(root, 0, 0, -1) do
    local rule_text = ts.get_node_text(node, data)
    table.insert(rule_sets, rule_text)
  end

  return rule_sets
end

local function deindent(text)
  -- First remove the leading whitespace of each line
  text = text:gsub("[\n\r]+%s*", "\n")

  -- check if there is only one line
  if not text:find("\n") then
    -- add a newline after ,
    text = text:gsub(",%s*", ",\n")
    -- add a space before { and a newline after
    text = text:gsub("%s*{%s*", " {\n\t")
    -- add a newline before }
    text = text:gsub("%s*}%s*", "\n}")
    -- add a newline after ;
    text = text:gsub(";%s*", ";\n\t")
  else
    -- For multi-line text, continue to use the original de-indentation logic
    local indent = string.match(text, "^%s*")
    if indent then
      text = string.gsub(string.gsub(text, '^' .. indent, ''), '\n' .. indent, '\n')
    end
  end

  return text
end


---@async
M.read_local_files = a.wrap(function(hrefs, cb)
  local files = hrefs
  if #files == 0 then
    cb({}, {})
  else
    a.run(function()
      classes = {} -- clean up prev classes
      ids = {}
      for _, file in ipairs(files) do
        ---@type string
        local file_name = u.get_file_name(file, "[^/]+$")

        local fd = io.open(file, "r")
        local data = fd:read("*a")
        fd:close()

        -- reading html files
        -- local _, fd = a.uv.fs_open(file, "r", 438)
        -- local _, stat = a.uv.fs_fstat(fd)
        -- local _, data = a.uv.fs_read(fd, stat.size, 0)
        -- a.uv.fs_close(fd)

        local rule_sets = extract_rule_sets(data, rule_set_qs)

        ---@type string[]
        local unique_class = {}
        local unique_class_rule_set = {}
        local unique_ids = {}
        local unique_ids_rule_set = {}

        for _, rule in ipairs(rule_sets) do
          a.util.scheduler()
          local parser = ts.get_string_parser(rule, "css")
          local tree = parser:parse()[1]
          local root = tree:root()
          local query = ts.query.parse("css", qs)

          for _, matches, _ in query:iter_matches(root, rule, 0, 0, {}) do
            local last_chid_node = ''
            for _, node in pairs(matches) do
              if node:type() == "id_name" then
                last_chid_node = node:type()
                local id_name = ts.get_node_text(node, rule)
                table.insert(unique_ids, id_name)
                table.insert(unique_ids_rule_set, rule)
              elseif node:type() == "class_name" then
                last_chid_node = node:type()
                local class_name = ts.get_node_text(node, rule)
                table.insert(unique_class, class_name)
                table.insert(unique_class_rule_set, rule)
              end
            end
          end
        end

        -- local unique_list = u.unique_list(unique_class)
        local unique_list, unique_block_list = u.unique_list_with_sync(unique_class, unique_class_rule_set)
        -- local unique_list, unique_block_list = unique_class, unique_class_rule_set
        for _, class in ipairs(unique_list) do
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
        unique_list, unique_block_list = u.unique_list_with_sync(unique_ids, unique_ids_rule_set)
        -- unique_list, unique_block_list = unique_ids, unique_ids_rule_set
        for _, id in ipairs(unique_list) do
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
      end
      cb(classes, ids)
    end)
  end
end, 2)

return M
