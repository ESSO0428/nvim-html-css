# ☕ Neovim HTML, CSS Support

## 🚧 plugin is in dev mod 🚧

Neovim CSS Intellisense for HTML/HTMLDJANGO

#### HTML/HTMLDJANGO `id` and `class` attribute completion for Neovim.

<br />

![image](https://github.com/ESSO0428/nvim-html-css/assets/92996726/ba0a8e9e-39bc-4da3-a34f-11b6936cc740)



## ✨ Features

- HTML/HTMLDJANGO `id` and `class` attribute completion.
- Supports `linked` and `embedded` style sheets.
- Supports additional `style sheets`.

## ⚡ Required dependencies

- NVIM v0.9.5 or higher
  - For treesitter support for filetype htmldjango, which can provide link css in extends html template
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [sharkdp/fd](https://github.com/sharkdp/fd) (finder)

## 📦 Installation

##### ⚠️ In case your tree-sitter is lazy loaded, you must also lazy load the html-css plugin in the same way as the tree-sitter. Another way is to add dependencies as in the example below.

## Lazy

```lua
return require("lazy").setup({
    {
        "hrsh7th/nvim-cmp",
        opts = {
            sources = {
                -- other sources
                {
                    name = "html-css",
                    option = {
                        -- your configuration here
                    },
                },
            },
        },
    },
    { "ESSO0428/nvim-html-css",
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-lua/plenary.nvim"
        }
    }
})
```

## ⚙ Configuration

```lua
option = {
    enable_on = {
      "htmldjango",
      "html"
    },                                           -- set the file types you want the plugin to work on
    file_extensions = { "css", "sass", "less" }, -- set the local filetypes from which you want to derive classes
    style_sheets = {
        -- example of remote styles, only css no js for now
        "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css",
        "https://cdn.jsdelivr.net/npm/bulma@0.9.4/css/bulma.min.css",
    }
}
```

#### 🔌 Option spec

explanation and types for options.

| Property        |  Type  | Description                                                                                                     |
| :-------------- | :----: | :-------------------------------------------------------------------------------------------------------------- |
| max_count       | number | Max item in cmp menu                                                                                            |
| enable_on       | table  | Table accepts strings, one string one extension in which the plugin will be available                           |
| file_extensions | table  | Table accepts strings, extensions that you enter, classes that will be available to you will be read from them. |
| style_sheets    | table  | External cdn css styles such as bootstrap or bulma. The link must be valid. Can be minified version or normal.  |

## 🤩 Pretty Menu Items

Setting the formatter this way you will get the file name with an extension in
your cmp menu, so you know from which file that class coming.

```lua
require("cmp").setup({
    sources = {
        {
            name = "html-css"
        },
    },
    formatting = {
        format = function(entry, vim_item)
            if entry.source.name == "html-css" then
                -- won't work
                -- vim_item.menu = entry.source.menu
                -- use this
                vim_item.menu = entry.completion_item.menu
            end
            return vim_item
        end
    }

})
```
