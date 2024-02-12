local M = {}

local a = require("plenary.async")
local c = require("plenary.curl")
local u = require("html-css.utils.init")
local cmp = require("cmp")
local ts = vim.treesitter
local Path = require("plenary.path")

---@type table<item>[]
local classes = {}

---@type string[]
local unique_class = {}
local unique_class_rule_set = {}
local unique_ids = {}
local unique_ids_rule_set = {}


---@type string
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


local function deindent(text)
  local indent = string.match(text, '^%s*')
  if not indent then
    return text
  end
  return string.gsub(string.gsub(text, '^' .. indent, ''), '\n' .. indent, '\n')
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

    if status ~= 200 then
      return {}
    end

    -- clean tables to avoid duplications
    classes = {}
    unique_class = {}

    local parser = ts.get_string_parser(body, "css", nil)
    local tree = parser:parse()[1]
    local root = tree:root()
    local query = ts.query.parse("css", qs)

    for _, matches, _ in query:iter_matches(root, body, 0, 0, {}) do
      local last_chid_node = ''
      for _, node in pairs(matches) do
        if node:type() == "id_name" then
          last_chid_node = node:type()
          local id_name = ts.get_node_text(node, body)
          table.insert(unique_ids, id_name)
        elseif node:type() == "class_name" then
          last_chid_node = node:type()
          local class_name = ts.get_node_text(node, body)
          table.insert(unique_class, class_name)
        end
        if node:type() == "rule_set" then
          if last_chid_node == "id_name" then
            local id_block = ts.get_node_text(node, body)
            table.insert(unique_ids_rule_set, id_block)
          elseif last_chid_node == "class_name" then
            local class_block = ts.get_node_text(node, body)
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
    cb(classes)
  end)
end, 2)

return M
