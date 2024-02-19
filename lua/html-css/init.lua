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
  self.remote_ids = {}
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
  self.remote_style_sheets = {}
  self.enable_on = self.option.enable_on or {}

  self.last_html_buffer = ''
  -- self.href_links = h.get_hrefs()

  -- merge lings together
  -- self.style_sheets = mrgtbls(self.style_sheets, self.href_links)

  -- set autocmd to update completion data when file is opened
  local augroup = vim.api.nvim_create_augroup('HTMLCSSCompletionForceUpdate', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinEnter' }, {
    group = augroup,
    pattern = { '*.html' },
    callback = function()
      if self.last_html_buffer == vim.api.nvim_get_current_buf() then
        return
      else
        self.last_html_buffer = vim.api.nvim_get_current_buf()
      end
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

local function add_items(self, buffer_id, item)
  -- Ensure that the items table of the buffer exists
  if not self.items[buffer_id] then
    self.items[buffer_id] = {}
  end
  self.items[buffer_id] = self.items[buffer_id] or {}
  -- Add items to the items of the specified buffer
  table.insert(self.items[buffer_id], item)
end

local function add_ids(self, buffer_id, id)
  -- Ensure that the ids table of the buffer exists
  if not self.ids[buffer_id] then
    self.ids[buffer_id] = {}
  end
  self.ids[buffer_id] = self.ids[buffer_id] or {}
  -- Add items to the ids of the specified buffer
  table.insert(self.ids[buffer_id], id)
end

local function check_update_completion(self)
  if self.update_done == 'done' then
    return
  end
  if self.embedded and self.remote and self.remote_item_write and self.local_file then
    self.after_inert_before_update = false
    self.update_done = 'done'
    print("html-css completion preloading done!")
  end
end

function source:update_completion_data(group_type)
  if group_type ~= 'condition' or self.after_inert_before_update then
    -- Reset flag immediately to prevent multiple triggers
    print("Load html-css completion data ...")
    vim.defer_fn(function()
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
        -- self.remote_classes = {}
        -- self.remote_ids = {}
        self.items = {}
        self.ids = {}
      end
      self.update_done = 'update'

      a.run(function()
        -- merge links together
        self.href_links = h.get_hrefs()
        -- self.style_sheets = self.option.style_sheets or {}
        self.style_sheets = mrgtbls(self.style_sheets, self.href_links)

        -- handle embedded styles
        e.read_html_files(function(classes, ids, links)
          for _, class in ipairs(classes) do
            -- table.insert(self.items, class)
            add_items(self, self.last_html_buffer, class)
          end
          for _, id in ipairs(ids) do
            -- table.insert(self.ids, id)
            add_ids(self, self.last_html_buffer, id)
          end
          self.style_sheets = mrgtbls(self.style_sheets, links)
          self.style_sheets = u.unique_list(self.style_sheets)
          self.embedded = 'done'
          check_update_completion(self)
        end)
      end)

      local buffer_id = self.last_html_buffer
      -- Remote css reading
      a.run(function()
        -- Separate remote style sheet URLs
        local current_remote_style_sheets = vim.tbl_filter(function(url)
          return url:match(self.isRemote)
        end, self.style_sheets)

        -- compare remote style sheets with cached remote style sheets
        if compare_tables(current_remote_style_sheets, self.remote_style_sheets) then
          -- use cached classes and ids to update completion items
          a.util.scheduler()
          local process_classes_and_ids = function()
            for _, class in ipairs(self.remote_classes) do
              if not vim.tbl_contains(self.items, class) then
                -- table.insert(self.items, class)
                add_items(self, buffer_id, class)
              end
            end
            for _, id in ipairs(self.remote_ids) do
              if not vim.tbl_contains(self.ids, id) then
                -- table.insert(self.ids, id)
                add_ids(self, buffer_id, id)
              end
            end
            self.remote = 'done'
            self.remote_item_write = 'done'
            check_update_completion(self)
          end
          a.wrap(process_classes_and_ids, 0)()
        else
          -- clear previous data
          self.remote_classes = {}
          self.remote_ids = {}
          -- update cached remote style sheets
          self.remote_style_sheets = vim.deepcopy(current_remote_style_sheets)

          -- process each remote style sheet
          for _, url in ipairs(current_remote_style_sheets) do
            a.util.scheduler()
            r.init(url, function(classes, ids)
              for _, class in ipairs(classes) do
                table.insert(self.remote_classes, class)
                -- table.insert(self.items, class)
                add_items(self, buffer_id, class)
              end
              for _, id in ipairs(ids) do
                table.insert(self.remote_ids, id)
                -- table.insert(self.ids, id)
                add_ids(self, buffer_id, id)
              end
              self.remote = 'done'
              self.remote_item_write = 'done'
              check_update_completion(self)
            end)
          end
        end
      end)

      -- Local css reading
      a.run(function()
        -- Yield control to other async tasks
        a.util.scheduler()
        l.read_local_files(self.style_sheets, function(classes, ids)
          for _, class in ipairs(classes) do
            table.insert(self.items, class)
            add_items(self, buffer_id, class)
          end
          for _, id in ipairs(ids) do
            table.insert(self.ids, id)
            add_ids(self, buffer_id, id)
          end
          self.local_file = 'done'
          check_update_completion(self)
        end)
      end)
    end, 2500)
  end
end

function source:complete(_, callback)
  if self.update_done == 'done' then
    local buffer_id = vim.api.nvim_get_current_buf()
    if self.current_selector == "class" then
      -- callback({ items = self.items, isComplete = false })
      callback({ items = self.items[buffer_id], isComplete = false })
    elseif self.current_selector == "id" then
      -- callback({ items = self.ids, isComplete = false })
      callback({ items = self.ids[buffer_id], isComplete = false })
    end
  end
end

function source:is_available()
  if self.update_done ~= 'done' then
    return false
  end

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
