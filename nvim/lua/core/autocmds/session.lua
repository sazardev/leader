-- ── Session: periodic autosave ───────────────────────────────────────────────
-- persistence.nvim only saves on exit; with a power cut nvim never reaches
-- `VimLeavePre`. Here it saves in the background (if something changed).
-- The Herdr registration lives in core/autocmds/herdr.lua.
local settings = require "core.settings"

local M = {}

local CHANGED =
  { "BufEnter", "BufWinEnter", "BufDelete", "WinClosed", "WinNew", "WinResized", "VimResized", "CursorHold" }

--- Is any real file open? (same as persistence: otherwise saving is pointless)
local function has_files()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      return true
    end
  end
  return false
end

--- The chat panel lives in real splits: mksession would save its (nofile)
--- buffers as files and restore two ghost windows. Autosave waits until it is
--- hidden (on exit `close_auxiliary` closes it before the session is written).
---@return boolean
local function chat_open()
  local window = package.loaded["agent.chat.window"]
  return window and window.is_open and window.is_open() or false
end

--- Saves without closing auxiliary windows (unlike on exit, here you are working)
local function autosave(group)
  local dirty = false
  vim.api.nvim_create_autocmd(CHANGED, {
    group = group,
    callback = function()
      dirty = true
    end,
  })

  local timer = assert(vim.uv.new_timer())
  local ms = settings.session.autosave_ms
  timer:start(
    ms,
    ms,
    vim.schedule_wrap(function()
      local ok, persistence = pcall(require, "persistence")
      if dirty and ok and persistence.active() and has_files() and not chat_open() then
        dirty = false
        pcall(persistence.save)
      end
    end)
  )
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      timer:stop()
      timer:close()
    end,
  })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("SessionAutosave", { clear = true })

  if settings.session.autosave_ms > 0 and #vim.api.nvim_list_uis() > 0 then
    autosave(group)
  end

  -- A bare `leader` inside a project brings its windows, files and terminals back. This runs in VimEnter BEFORE
  -- ui.start's (session is set up earlier in core/autocmds/init.lua), so the start screen is never opened and thrown
  -- away: with no session, ui.start opens it normally.
  if settings.session.auto_restore and #vim.api.nvim_list_uis() > 0 then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      callback = function()
        require("utils.session").auto_restore()
      end,
    })
    -- If nvim exits before the scheduled plugin load (a session restored and closed in the same breath), make sure
    -- the session is still written. Normally persistence is already loaded here and its own VimLeavePre does it.
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        if not package.loaded["persistence"] then
          local ok, p = pcall(require, "persistence")
          if ok then
            pcall(p.save)
          end
        end
      end,
    })
  end
end

return M
