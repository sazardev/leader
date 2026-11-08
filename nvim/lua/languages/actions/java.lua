-- ── Java actions (JVM common + setup) ────────────────────────────────────────
local base = require "languages.actions.jvm"
local maps = vim.list_extend({}, base)
return vim.list_extend(maps, require("langsetup").maps "java")
