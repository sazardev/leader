-- ── Lua actions (format + project setup) ────────────────────────────────────
local actions = require "utils.actions"
local maps = {
  { "f", "format", actions.format },
}
return vim.list_extend(maps, require("langsetup").maps "lua")
