local M = {}

local a = require("plenary.async")
local c = require("plenary.curl")
local u = require("html-css.utils.init")
local cmp = require("cmp")
local ts = vim.treesitter
local Path = require("plenary.path")

---@type table<item>[]
local classes = {}
local ids = {}

---@type string[]
local unique_class = {}
local unique_class_rule_set = {}
local unique_ids = {}
local unique_ids_rule_set = {}

---@type string
local rule_set_qs = [[
  (rule_set) @rule
]]

---@type string
local qs = [[
	(id_selector
		(id_name)@id_name)
	(class_selector
		(class_name)@class_name)
]]



-- (selectors . (class_selector . (class_name) @class-name))
-- (id_name) @id_name

local function ensure_cache_dir()
  local cache_dir = Path:new(vim.fn.stdpath("cache"), "html-css")
  if not cache_dir:exists() then
    cache_dir:mkdir()
  end
  return cache_dir
end

local function get_cache_file_path(url)
  local cache_dir = ensure_cache_dir()
  local file_name = u.get_file_name(url, "[^/]+$")
  return cache_dir:joinpath(file_name)
end

---@param url string
---@param cb function
---@async
local get_remote_styles = a.wrap(function(url, cb)
  local cache_file_path = get_cache_file_path(url)
  if cache_file_path:exists() then
    local body = cache_file_path:read()
    cb(200, body) -- Assuming success if cache exists
    return
  end

  c.get(url, {
    callback = function(res)
      if res.status == 200 then
        -- Save to cache if successful
        cache_file_path:write(res.body, "w")
      end
      cb(res.status, res.body)
    end,
    on_error = function(err)
      print("[html-css] Unable to connect to the URL:", url, err)
      cb(nil, nil) -- Handle error case
    end,
  })
end, 2)

local function extract_rule_sets(body, rule_set_qs)
  local parser = ts.get_string_parser(body, "css")
  local tree = parser:parse()[1]
  local root = tree:root()
  local query = ts.query.parse("css", rule_set_qs)
  local rule_sets = {}

  for id, node in query:iter_captures(root, 0, 0, -1) do
    local rule_text = ts.get_node_text(node, body)
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


---@param url string
---@param cb function
M.init = a.wrap(function(url, cb)
  if not url then
    return {}
  end

  get_remote_styles(url, function(status, body)
    ---@ type string
    local file_name = u.get_file_name(url, "[^/]+$")
    file_name = table.concat({ "󰖟", file_name }, " ")

    if status ~= 200 then
      return {}
    end

    local rule_sets = extract_rule_sets(body, rule_set_qs)

    -- clean tables to avoid duplications
    classes = {}
    ids = {}
    unique_class = {}
    unique_class_rule_set = {}
    unique_ids = {}
    unique_ids_rule_set = {}

    a.run(function()
      for _, rule in ipairs(rule_sets) do
        a.util.scheduler()
        local parser = ts.get_string_parser(rule, "css", nil)
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
      -- local unique_list, unique_block_list = u.unique_list_with_sync(unique_class, unique_class_rule_set)
      local unique_list, unique_block_list = unique_class, unique_class_rule_set
      for _, class in ipairs(unique_list) do
        table.insert(classes, {
          label = class,
          kind = cmp.lsp.CompletionItemKind.Enum,
          menu = file_name,
          file_path = url,
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
      unique_list, unique_block_list = unique_ids, unique_ids_rule_set
      for _, id in ipairs(unique_list) do
        table.insert(ids, {
          label = id,
          kind = cmp.lsp.CompletionItemKind.Enum,
          menu = file_name,
          file_path = url,
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
    end)
  end)
end, 2)

return M
