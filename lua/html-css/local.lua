local M = {}
local a = require("plenary.async")
local u = require("html-css.utils.init")
local j = require("plenary.job")
local cmp = require("cmp")
local ts = vim.treesitter

---@type table<item>[]
local classes = {}
local ids = {}

---@type string[]
local unique_class = {}
local unique_class_rule_set = {}
local unique_ids = {}
local unique_ids_rule_set = {}

-- treesitter query for extracting css clasess
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


local function deindent(text)
  local indent = string.match(text, '^%s*')
  if not indent then
    return text
  end
  return string.gsub(string.gsub(text, '^' .. indent, ''), '\n' .. indent, '\n')
end


---@async
M.read_local_files = a.wrap(function(hrefs, cb)
  local files = {}
  for _, href in ipairs(hrefs) do
    if not href:match("^http") then
      j:new({
        command = "fd",
        args = { ".", href, "--exclude", "node_modules" },
        on_stdout = function(_, data)
          table.insert(files, data)
        end,
      }):sync()

      -- use ** pattern search
      if href:sub(1, 1) == "/" then
        j:new({
          command = "fd",
          args = { "-p", "-g", "**" .. href },
          on_stdout = function(_, data)
            table.insert(files, data)
          end,
        }):sync()
      end
    end
  end
  if #files == 0 then
    return {}, {}
  else
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

      unique_class = {}
      unique_class_rule_set = {}
      unique_ids = {}
      unique_ids_rule_set = {}

      local parser = ts.get_string_parser(data, "css")
      local tree = parser:parse()[1]
      local root = tree:root()
      local query = ts.query.parse("css", qs)

      for _, matches, _ in query:iter_matches(root, data, 0, 0, {}) do
        local last_chid_node = ''
        for _, node in pairs(matches) do
          if node:type() == "id_name" then
            last_chid_node = node:type()
            local id_name = ts.get_node_text(node, data)
            table.insert(unique_ids, id_name)
          elseif node:type() == "class_name" then
            last_chid_node = node:type()
            local class_name = ts.get_node_text(node, data)
            table.insert(unique_class, class_name)
          end
          if node:type() == "rule_set" then
            if last_chid_node == "id_name" then
              local id_block = ts.get_node_text(node, data)
              table.insert(unique_ids_rule_set, id_block)
            elseif last_chid_node == "class_name" then
              local class_block = ts.get_node_text(node, data)
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
    end
    cb(classes, ids)
  end
end, 2)

return M
