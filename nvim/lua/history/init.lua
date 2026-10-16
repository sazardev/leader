-- ── Undo, redo, clipboard and yank history ───────────────────────────────────
-- One place for what "editing history" means, closer to VS Code without changing Vim's own model:
--   undo.lua    u undoes word by word in insert mode, undo/redo flash what changed, U / Ctrl+Y redo, Ctrl+Z undo,
--               the undo tree and the file as it was at the previous / next save
--   yanks.lua   every yank and cut kept newest first; [y / ]y swap what you just pasted
--   picker.lua  the list (<leader>uy)
-- Clipboard: with `settings.clipboard.keep`, x and c delete into the black hole register and pasting over a
-- selection keeps the clipboard, so only y and d fill it. The menu is menus/history.lua. Nothing runs until used:
-- two autocmds (TextChangedI is a few comparisons) and the keymaps.
local M = {}

local function settings()
  return require "core.settings"
end

--- The register a key without an explicit `"x` prefix writes to
---@return boolean
local function default_register()
  local reg = vim.v.register
  return reg == '"'
    or (reg == "+" and vim.o.clipboard:find "unnamedplus" ~= nil)
    or (reg == "*" and vim.o.clipboard:find "unnamed" ~= nil)
end

--- `lhs`, or `"_lhs` when the clipboard must survive it
---@param lhs string
---@param keep string what to type instead (default: `"_` .. lhs)
local function keeping(lhs, keep)
  return function()
    if settings().clipboard.keep and default_register() then
      return keep or ('"_' .. lhs)
    end
    return lhs
  end
end

function M.setup()
  local map = vim.keymap.set
  local undo = require "history.undo"
  local yanks = require "history.yanks"
  undo.setup()

  map("n", "u", undo.undo, { desc = "History undo (flashes what changed)" })
  map("n", "<C-r>", undo.redo, { desc = "History redo (flashes what changed)" })
  if settings().history.redo_keys ~= false then
    map("n", "U", undo.redo, { desc = "History redo (U)" })
    map("n", "<C-y>", undo.redo, { desc = "History redo (Ctrl+Y)" })
    map("n", "<C-z>", undo.undo, { desc = "History undo (Ctrl+Z, never suspends nvim)" })
    map("i", "<C-z>", "<C-o>u", { desc = "History undo in insert mode" })
  end

  map("n", "p", yanks.paste "p", { desc = "History paste after ([y / ]y swap it)" })
  map("n", "P", yanks.paste "P", { desc = "History paste before ([y / ]y swap it)" })
  map("n", "[y", function()
    yanks.cycle(1)
  end, { desc = "History older yank in place of the paste" })
  map("n", "]y", function()
    yanks.cycle(-1)
  end, { desc = "History newer yank in place of the paste" })

  local expr = { expr = true }
  for _, lhs in ipairs { "x", "X", "c", "C" } do
    map(
      { "n", "x" },
      lhs,
      keeping(lhs),
      vim.tbl_extend("force", expr, { desc = "Clipboard " .. lhs .. " without copying" })
    )
  end
  map("x", "p", keeping("p", "P"), vim.tbl_extend("force", expr, { desc = "Clipboard paste over keeps it" }))

  local group = vim.api.nvim_create_augroup("HistoryYanks", { clear = true })
  vim.api.nvim_create_autocmd("TextYankPost", { group = group, callback = yanks.on_yank })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      yanks.save()
    end,
  })
end

return M
