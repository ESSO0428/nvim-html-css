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

local function compare_tables(t1, t2)
  -- check if the length of the tables are the same
  if #t1 ~= #t2 then return false end

  -- copy and sort the tables to avoid modifying the original data
  local copy1, copy2 = {}, {}
  for i, v in ipairs(t1) do table.insert(copy1, v) end
  for i, v in ipairs(t2) do table.insert(copy2, v) end

  table.sort(copy1)
  table.sort(copy2)

  -- compare each item
  for i = 1, #copy1 do
    if copy1[i] ~= copy2[i] then return false end
  end

  return true
end

source.new = function()
  local self = setmetatable({}, { __index = source })
  self.source_name = "html-css"
  self.isRemote = "^https?://"
  self.remote_classes = {}
  self.items = {}
  self.ids = {}
  self.href_links = {}
  self.after_inert_before_update = false

  self.embedded = ''
  self.remote = ''
  self.remote_item_write = ''
  self.local_file = ''
  self.update_done = ''

  -- reading user config
  self.user_config = config.get_source_config(self.source_name) or {}
  self.option = self.user_config.option or {}
  self.file_extensions = self.option.file_extensions or {}
  self.style_sheets = self.option.style_sheets or {}
  self.enable_on = self.option.enable_on or {}

  -- self.href_links = h.get_hrefs()

  -- merge lings together
  -- self.style_sheets = mrgtbls(self.style_sheets, self.href_links)

  -- set autocmd to update completion data when file is opened
  local augroup = vim.api.nvim_create_augroup('HTMLCSSCompletionForceUpdate', { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'BufReadPost' }, {
    group = augroup,
    pattern = { '*.html' },
    callback = function()
      local status = (self.update_done ~= "" and self.update_done) or 'NA'
      print(table.concat({ 'last html-css-completion update status:', status }, " "))
      while not self.update_done == 'update' do
        a.wait(50)
      end
      if self.update_done == '' or self.update_done == 'done' then
        self.after_inert_before_update = true
        self:update_completion_data('force')
      end
    end
  })
  local augroup = vim.api.nvim_create_augroup('HTMLCSSCompletionTextChange', { clear = true })
  vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
    group = augroup,
    pattern = { '*.html' },
    callback = function()
      if self.update_done == '' or self.update_done == 'done' then
        local inside_quotes = ts.get_node({ bfnr = 0, lang = 'html' })

        if inside_quotes ~= nil then
          local type = inside_quotes:type()

          local prev_sibling = inside_quotes:prev_named_sibling()
          if prev_sibling ~= nil then
            local prev_sibling_name = ts.get_node_text(prev_sibling, 0)

            if prev_sibling_name == "href" then
              self.after_inert_before_update = true
            end
          end
        end
      end
    end
  })
  local augroup = vim.api.nvim_create_augroup('HTMLCSSCompletionLinkChange', { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged' }, {
    group = augroup,
    pattern = { '*.html' },
    callback = function()
      -- check link href wheather it is changed
      if not compare_tables(self.href_links, h.get_hrefs()) then
        self.after_inert_before_update = true
      end
    end
  })


  local augroup = vim.api.nvim_create_augroup('HTMLCSSCompletionConditionUpdate', { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorHold' }, {
    group = augroup,
    pattern = { '*.html' },
    callback = function()
      if self.update_done == '' or self.update_done == 'done' then
        self:update_completion_data('condition')
      end
    end
  })
  return self
end

function source:check_update_completion()
  if self.embedded and self.remote and self.remote_item_write and self.local_file then
    self.after_inert_before_update = false
    self.update_done = 'done'
    print("html-css completion preloading done!")
  end
end

function source:update_completion_data(group_type)
  if group_type ~= 'condition' or self.after_inert_before_update then
    -- Reset flag immediately to prevent multiple triggers
    vim.defer_fn(function()
      print("Load html-css completion data ...")
      if not vim.tbl_contains(self.option.enable_on, vim.bo.filetype) then
        self.update_done = 'done'
        print("Load html-css completion stop!")
        return
      end
      if group_type == 'condition' and self.after_inert_before_update == false then
        return
      end
      if self.update_done == '' or self.update_done == 'done' then
        self.embedded = ''
        self.remote = ''
        self.remote_item_write = ''
        self.local_file = ''
        self.remote_classes = {}
        self.items = {}
        self.ids = {}
      end
      self.update_done = 'update'

      a.run(function()
        -- if self.embedded == 'done' and self.update_done == 'update' then
        --   return
        -- end
        -- merge links together
        self.href_links = h.get_hrefs()
        self.style_sheets = self.option.style_sheets or {}
        self.style_sheets = mrgtbls(self.style_sheets, self.href_links)
        -- handle embedded styles
        e.read_html_files(function(classes, ids, links)
          for _, class in ipairs(classes) do
            table.insert(self.items, class)
          end
          for _, id in ipairs(ids) do
            table.insert(self.ids, id)
          end
          self.style_sheets = mrgtbls(self.style_sheets, links)
          self.style_sheets = u.unique_list(self.style_sheets)
          self.embedded = 'done'
          self:check_update_completion()
        end)
      end)

      -- Remote css reading
      a.run(function()
        -- if self.remote == 'done' and self.update_done == 'update' then
        --   return
        -- end
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
        end
        self.remote = 'done'
        self:check_update_completion()
      end)

      -- Local css reading
      a.run(function()
        -- if self.local_file == 'done' and self.update_done == 'update' then
        --   return
        -- end
        self.local_file = ''
        l.read_local_files(self.style_sheets, function(classes, ids)
          for _, class in ipairs(classes) do
            table.insert(self.items, class)
          end
          for _, id in ipairs(ids) do
            table.insert(self.ids, id)
          end
        end)
        self.local_file = 'done'
      end)
      a.run(function()
        -- if self.remote_item_write == 'done' or self.remote ~= 'done' then
        --   return
        -- end
        for _, class in ipairs(self.remote_classes) do
          table.insert(self.items, class)
        end
        self.remote_item_write = 'done'
        self:check_update_completion()
      end)
    end, 5000)
  end
end

function source:complete(_, callback)
  if self.update_done == 'done' then
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
