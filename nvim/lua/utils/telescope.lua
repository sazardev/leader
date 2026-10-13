-- ── telescope entry_maker without icons ──────────────────────────────────────
-- The icons come from nvim-web-devicons and can't be turned off with a flag: you
-- have to override the entry_maker that builds each result.
--
-- IMPORTANT: the telescope require goes INSIDE the display closure. At module
-- level it would fail on a clean install: lazy evaluates the specs BEFORE
-- telescope is on the runtimepath.
local M = {}

---@return fun(line: string): table
function M.no_icons()
  local displayer -- memo: created the first time an entry is displayed

  return function(line)
    return {
      value = line,
      path = line,
      ordinal = line,
      display = function(entry)
        if not displayer then
          displayer = require("telescope.pickers.entry_display").create {
            separator = " ",
            items = {
              { width = 1 }, -- padding (it used to be the icon)
              { remaining = true }, -- full path
            },
          }
        end
        return displayer { { "" }, entry.path }
      end,
    }
  end
end

return M
