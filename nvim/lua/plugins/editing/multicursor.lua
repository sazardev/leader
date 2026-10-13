-- Real multiple cursors (VS Code / Helix style). Only loads on the first key;
-- with a single cursor nothing runs (no residual autocmds or polling).
--
-- Chosen so as not to override anything: <C-n> is nvim-tree (NvChad), <leader>x/n/A are menu
-- prefixes, <C-LeftMouse> is "go to definition" and <A-hjkl> is mini.move.
local function mc()
  return require "multicursor-nvim"
end

local function key(lhs, fn, desc, modes)
  return { lhs, fn, mode = modes or { "n", "x" }, desc = "Multicursor " .. desc }
end

return {
  "jake-stewart/multicursor.nvim",
  branch = "1.0",
  keys = {
    key("<C-Up>", function()
      mc().lineAddCursor(-1)
    end, "add cursor above"),
    key("<C-Down>", function()
      mc().lineAddCursor(1)
    end, "add cursor below"),
    key("<A-n>", function()
      mc().matchAddCursor(1)
    end, "add next match"),
    key("<A-N>", function()
      mc().matchSkipCursor(1)
    end, "skip next match"),
    key("<A-p>", function()
      mc().matchAddCursor(-1)
    end, "add previous match"),
    key("<A-P>", function()
      mc().matchSkipCursor(-1)
    end, "skip previous match"),
    key("<A-a>", function()
      mc().matchAllAddCursors()
    end, "add cursor on every match"),
    key("<A-LeftMouse>", function()
      mc().handleMouse()
    end, "toggle cursor at mouse", { "n" }),
  },
  config = function()
    local m = mc()
    m.setup()

    -- Mapping layer: only exists while there are multiple cursors
    m.addKeymapLayer(function(layer)
      layer({ "n", "x" }, "<Left>", m.prevCursor, { desc = "Multicursor previous cursor" })
      layer({ "n", "x" }, "<Right>", m.nextCursor, { desc = "Multicursor next cursor" })
      layer({ "n", "x" }, "<A-x>", m.deleteCursor, { desc = "Multicursor delete cursor" })
      layer({ "n", "x" }, "<C-q>", m.toggleCursor, { desc = "Multicursor toggle cursor" })
      layer("n", "<Esc>", function()
        if not m.cursorsEnabled() then
          m.enableCursors()
        else
          m.clearCursors()
        end
      end, { desc = "Multicursor clear cursors" })
    end)
  end,
}
