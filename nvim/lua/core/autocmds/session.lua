-- ── Sesión: autoguardado periódico + registro en Herdr ───────────────────────
-- persistence.nvim solo guarda al salir; con un corte de luz nvim no llega a
-- `VimLeavePre`. Aquí se guarda en segundo plano (si algo cambió) y se avisa a
-- Herdr para que reabra este pane con la sesión (ver utils/herdr.lua).
local settings = require "core.settings"

local M = {}

local CHANGED = { "BufEnter", "BufWinEnter", "BufDelete", "WinClosed", "WinNew", "CursorHold" }

--- ¿Hay algún archivo real abierto? (igual que persistence: si no, no vale la pena guardar)
local function has_files()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      return true
    end
  end
  return false
end

--- Guarda sin cerrar las ventanas auxiliares (a diferencia de la salida, aquí estás trabajando)
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
  end, { desc = "Restaura la sesión de la carpeta (comando de resume de Herdr)" })

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
