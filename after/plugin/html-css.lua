-- require("html-css"):setup()
local ok, cmp = pcall(require, "cmp")

if ok then
  cmp.register_source("html-css", require('html-css').new())
end
