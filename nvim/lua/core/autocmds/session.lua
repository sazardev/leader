-- ── Session: periodic autosave + Herdr registration ──────────────────────────
-- persistence.nvim only saves on exit; with a power cut nvim never reaches
-- `VimLeavePre`. Here it saves in the background (if something changed) and
-- notifies Herdr so it reopens this pane with the session (see utils/herdr.lua).
local settings = require "core.settings"

local M = {}

local CHANGED = { "BufEnter", "BufWinEnter", "BufDelete", "WinClosed", "WinNew", "CursorHold" }

--- Is any real file open? (same as persistence: otherwise saving is pointless)
local function has_files()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      return true
    end
  end
  return false
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
      if dirty and ok and persistence.active() and has_files() then
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

  vim.api.nvim_create_user_command("HerdrResume", function()
    require("utils.herdr").resume()
  end, { desc = "Restore the folder's session (Herdr resume command)" })

  if settings.session.herdr then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      callback = function()
        require("utils.herdr").attach()
      end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        require("utils.herdr").release()
      end,
    })
  end
end

return M
