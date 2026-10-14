-- ── Flat design ──────────────────────────────────────────────────────────────
-- One module that gives the whole editor the look of the landing page's demo: filled blocks instead of boxes,
-- selection in solid blue, yellow matches and keys, purple groups, faint hints, and a "just changed" flash.
-- `palette.lua` derives a handful of tokens from the active theme, `groups.lua` turns them into highlight groups,
-- and this file applies them whenever the theme (or a plugin that defines its own colors) changes.
-- Plugins read `M.BORDER` (or inherit 'winborder') for their `border` option and `FloatBorder` makes it invisible.
-- Off with `settings.ui.flat = false`.
local settings = require "core.settings"

local M = {}

--- `solid` = one blank cell of padding around the content; with `FloatBorder` painted like the block it is air, not a line
M.BORDER = "solid"

--- Compact popups (hover, diagnostics, signature, docs) only get air on the left and right, like the demo's floats
--- (6px above and below the text, not a whole row): `{ topleft, top, topright, right, botright, bottom, botleft, left }`
M.SIDE = { "", "", "", " ", "", "", "", " " }

--- A float that sits right of another block (completion docs): its left column is half gap, half block,
--- the demo's 2px gap between the list and its docs
M.BESIDE = { "", "", "", " ", "", "", "", { "▐", "FlatEdge" } }

--- Border for a window: invisible padding when flat, the usual line otherwise (what plugins pass as `border`).
--- `kind` = "float" for small popups next to the text, "beside" for one glued to the right of another block,
--- nothing (or "panel") for modals and panels.
---@param kind? "float"|"beside"|"panel"
---@return string|table
function M.border(kind)
  if not M.enabled() then
    return "single"
  end
  return kind == "float" and M.SIDE or kind == "beside" and M.BESIDE or M.BORDER
end

--- How many diagnostics the workspace has (the Trouble panel's header)
---@return integer
function M.diagnostic_total()
  return #vim.diagnostic.get()
end

---@return boolean
function M.enabled()
  return settings.ui.flat ~= false
end

local emitting = false

--- Defines every group from the active theme
function M.apply()
  if not M.enabled() then
    return
  end
  local groups = require "ui.flat.groups"
  local t = require("ui.flat.palette").current()
  local defs = groups.build(t)
  for name, def in
    pairs(groups.rebase(vim.api.nvim_get_hl(0, {}), tonumber(t.bg:sub(2), 16), tonumber(t.deep:sub(2), 16), defs))
  do
    vim.api.nvim_set_hl(0, name, def)
  end
  for name, def in pairs(defs) do
    vim.api.nvim_set_hl(0, name, def)
  end
  -- what derives its own colors from NormalFloat / Normal (agent, commit panel) recomputes now, not on the next theme change
  emitting = true
  vim.api.nvim_exec_autocmds("User", { pattern = "NvThemeReload", modeline = false })
  emitting = false
end

local pending = false

--- Same, once per tick however many plugins asked for it
function M.request()
  if pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    M.apply()
  end)
end

--- Neovim's built-in message UI (0.12+): no "Press ENTER" screen. Short messages (`"file" written`, errors,
--- warnings, a `print`) become notes (ui/flat/notify.lua: same size, colored by kind); listings, long output and
--- prompts stay in Neovim's own windows, styled as blocks; `g<` or `:messages` open the full pager.
function M.messages()
  local ok, ui2 = pcall(require, "vim._core.ui2")
  if not ok then
    return
  end
  if not pcall(ui2.enable, { msg = { target = "msg", msg = { timeout = 4000 } } }) then
    return
  end
  local msgs = package.loaded["vim._core.ui2.messages"]
  if msgs and not msgs._flat and require("core.settings").ui.notify then
    msgs._flat = true
    local show = msgs.msg_show
    -- the message UI looks the handler up on every message: the notes take the ones that read like notes
    msgs.msg_show = function(kind, content, replace_last, history, append, id, trigger)
      local busy = ui2.cmd and (ui2.cmd.prompt or (ui2.cmd.level or 0) > 0)
      if not (busy or replace_last or append) and require("ui.flat.notify").message(kind, content) then
        return
      end
      return show(kind, content, replace_last, history, append, id, trigger)
    end
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("FlatMessages", { clear = true }),
    pattern = { "msg", "pager", "dialog" },
    callback = function(ev)
      local win = vim.fn.bufwinid(ev.buf)
      if win == -1 then
        return
      end
      local search_hide = "Search:,CurSearch:,IncSearch:"
      if ev.match == "msg" then
        vim.wo[win].winhighlight = "Normal:FlatNotify,NormalFloat:FlatNotify," .. search_hide
        -- what still lands here (long output): a soft block with a thin bar down its whole left side and one row
        -- of editor between it and the statusline (the message UI re-places the window on every message, so that
        -- row is the window's bottom border, painted like the editor). One column of border only: the message UI
        -- sizes the window for exactly that, a second one would clip the last character
        local gap, bar = { " ", "FlatGap" }, { "▎", "FlatNotifyDebug" }
        pcall(vim.api.nvim_win_set_config, win, { border = { "", "", "", "", "", gap, gap, bar } })
      else
        vim.wo[win].winhighlight = "Normal:FlatNotify,NormalFloat:FlatNotify,MsgArea:FlatNotify," .. search_hide
      end
    end,
  })
end

function M.setup()
  if not M.enabled() then
    return
  end
  local ui = settings.ui

  vim.o.winborder = M.BORDER
  vim.o.showtabline = 0 -- no tab bar (diffview opens a tab): the demo's editor never shows one
  vim.opt.fillchars:append { vert = "│" }
  if ui.blink_cursor then
    vim.o.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,a:blinkwait700-blinkoff400-blinkon250"
  end

  local group = vim.api.nvim_create_augroup("FlatDesign", { clear = true })
  -- the theme changed, or a plugin just loaded and painted its own groups on top of ours
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.request })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "NvThemeReload", "LazyLoad", "VeryLazy" },
    callback = function()
      if not emitting then
        M.request()
      end
    end,
  })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
      require("ui.flat.fresh").on_yank()
    end,
  })

  -- LSP floats (hover, signature help) open with the compact border unless the caller asks for another one
  for _, name in ipairs { "hover", "signature_help" } do
    local original = vim.lsp.buf[name]
    vim.lsp.buf[name] = function(opts)
      opts = opts or {}
      opts.border = opts.border or M.SIDE
      return original(opts)
    end
  end

  if ui.notify then
    require("ui.flat.notify").setup()
  end
  if ui.messages ~= false then
    M.messages()
  end
  require("ui.flat.keys").setup()
  M.apply()
end

return M
