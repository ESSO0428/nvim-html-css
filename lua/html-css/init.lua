local source = {}
local config = require("cmp.config")
local a = require("plenary.async")
local Job = require("plenary.job")
local r = require("html-css.remote")
local l = require("html-css.local")
local e = require("html-css.embedded")
local h = require("html-css.hrefs")
local u = require("html-css.utils.init")

local ts = vim.treesitter

local function mrgtbls(t1, t2)
  for _, v in ipairs(t2) do
    table.insert(t1, v)
  end
  return t1
end

source.new = function()
  local self = setmetatable({}, { __index = source })
  self.source_name = "html-css"
  self.isRemote = "^https?://"
  self.remote_classes = {}
  self.items = {}
  self.ids = {}
  self.href_links = {}

  self.embedded = ''
  self.remote = ''
  self.local_file = ''

  -- reading user config
  self.user_config = config.get_source_config(self.source_name) or {}
  self.option = self.user_config.option or {}
  self.file_extensions = self.option.file_extensions or {}
  self.style_sheets = self.option.style_sheets or {}
  self.enable_on = self.option.enable_on or {}

  self.href_links = h.get_hrefs()

  -- merge lings together
  self.style_sheets = mrgtbls(self.style_sheets, self.href_links)

  -- set autocmd to update completion data when file is opened
  local augroup = vim.api.nvim_create_augroup('HTMLCSSCompletion', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
    group = augroup,
    pattern = { '*.html' },
    callback = function()
      self:update_completion_data()
    end,
  })
  return self
end

function source:update_completion_data()
  self.remote_classes = {}
  self.items = {}
  self.ids = {}
  self.href_links = h.get_hrefs()
  self.style_sheets = self.option.style_sheets or {}

  self.embedded = ''
  self.remote = ''
  self.local_file = ''

  -- merge links together
  self.style_sheets = mrgtbls(self.style_sheets, self.href_links)

  -- handle embedded styles
  a.run(function()
    e.read_html_files(function(classes, ids, links)
      for _, class in ipairs(classes) do
        table.insert(self.items, class)
      end
      for _, id in ipairs(ids) do
        table.insert(self.ids, id)
      end
      self.style_sheets = mrgtbls(self.style_sheets, links)
      self.style_sheets = u.unique_list(self.style_sheets)
    end)
    self.embedded = 'done'
  end)

  -- Remote css reading
  a.run(function()
    if self.embedded == 'done' then
      for _, url in ipairs(self.style_sheets) do
        if url:match(self.isRemote) then
          a.run(function()
            r.init(url, function(classes)
              for _, class in ipairs(classes) do
                table.insert(self.remote_classes, class)
              end
            end)
          end)
        end
        self.remote = 'done'
      end
    end
  end)

  -- Local css reading
  a.run(function()
    l.read_local_files(self.href_links, function(classes, ids)
      for _, class in ipairs(classes) do
        table.insert(self.items, class)
      end
      for _, id in ipairs(ids) do
        table.insert(self.ids, id)
      end

      for _, class in ipairs(self.remote_classes) do
        table.insert(self.items, class)
      end
    end)
    self.local_file = 'done'
  end)
end

function source:complete(_, callback)
  if self.embedded == 'done' and self.remote == 'done' and self.local_file == 'done' then
    if self.current_selector == "class" then
      callback({ items = self.items, isComplete = false })
    elseif self.current_selector == "id" then
      callback({ items = self.ids, isComplete = false })
    end
  end
end

function source:is_available()
  if not next(self.user_config) then
    return false
  end

  if not vim.tbl_contains(self.option.enable_on, vim.bo.filetype) then
    return false
  end

  local inside_quotes = ts.get_node({ bfnr = 0, lang = 'html' })

  if inside_quotes == nil then
    return false
  end

  local type = inside_quotes:type()

  local prev_sibling = inside_quotes:prev_named_sibling()
  if prev_sibling == nil then
    return false
  end

  local prev_sibling_name = ts.get_node_text(prev_sibling, 0)

  if prev_sibling_name == "class" then
    self.current_selector = "class"
  elseif prev_sibling_name == "id" then
    self.current_selector = "id"
  end
  if prev_sibling_name == "class" or prev_sibling_name == "id" and type == "quoted_attribute_value" then
    return true
  end

  return false
end

return source
