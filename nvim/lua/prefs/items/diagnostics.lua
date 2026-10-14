-- Settings panel: diagnostics (see prefs/init.lua for the item contract). The blocks keep their own saved state
-- (utils/diagblocks.lua, also driven by <leader>xa / <leader>xc), so those two rows read and write it there.
local function blocks()
  return require "utils.diagblocks"
end

return {
  {
    group = "Diagnostics",
    label = "Inline blocks",
    kind = "toggle",
    get = function()
      return blocks().get().enabled
    end,
    apply = function(on)
      blocks().set { enabled = on }
    end,
  },
  {
    group = "Diagnostics",
    label = "Blocks layout",
    kind = "choice",
    choices = { { value = "expanded", label = "all open" }, { value = "compact", label = "one at a time" } },
    get = function()
      return blocks().get().mode
    end,
    apply = function(mode)
      blocks().set { enabled = true, mode = mode }
    end,
  },
  {
    group = "Diagnostics",
    label = "While typing",
    kind = "toggle",
    id = "diagnostics.update_in_insert",
    apply = function(on)
      vim.diagnostic.config { update_in_insert = on }
    end,
  },
}
