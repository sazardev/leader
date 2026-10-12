-- ── Herdr: nvim se registra como "agente" para que el pane se reabra tras un reinicio ──
-- Herdr restaura panes de agentes con el comando que ellos reportan. Aquí nvim
-- reporta `nvim +HerdrResume` (restaura la sesión de la carpeta) y lo libera al
-- salir, de modo que un `:q` normal no lo reabre. Solo actúa dentro de Herdr.
local M = {}

local SOURCE = "nvim"
local seq = 0

---@return boolean
local function inside_herdr()
  return vim.env.HERDR_ENV == "1" and (vim.env.HERDR_PANE_ID or "") ~= "" and (vim.env.HERDR_BIN_PATH or "") ~= ""
end

--- `--seq` debe crecer entre reportes y entre ejecuciones de nvim
local function next_seq()
  seq = seq + 1
  return tostring(os.time() * 1000 + seq)
end

---@param args string[] argumentos tras `pane`
---@return string[]
local function command(args)
  return vim.list_extend({ vim.env.HERDR_BIN_PATH, "pane" }, args)
end

--- Registra este nvim en el pane (async, los fallos se ignoran). No pisa a un
--- agente real (Claude, Codex...) que ya ocupe el pane: nvim puede abrirse desde él.
function M.attach()
  if not inside_herdr() or #vim.api.nvim_list_uis() == 0 then
    return
  end
  vim.system(command { "get", vim.env.HERDR_PANE_ID }, { text = true }, function(got)
    -- el callback corre en un contexto "fast": vim.env y compañía hay que llamarlos agendados
    vim.schedule(function()
      local ok, info = pcall(vim.json.decode, got.stdout or "")
      local pane = ok and type(info) == "table" and info.result and info.result.pane
      if not pane or (pane.agent ~= nil and pane.agent ~= vim.NIL) then
        return
      end
      vim.system(command {
        "report-agent", vim.env.HERDR_PANE_ID,
        "--source", SOURCE, "--agent", "nvim", "--state", "idle", "--seq", next_seq(),
        "--", "nvim", "+HerdrResume",
      })
    end)
  end)
end

--- Libera el pane (síncrono y corto: nvim está saliendo)
function M.release()
  if not inside_herdr() or #vim.api.nvim_list_uis() == 0 then
    return
  end
  pcall(function()
    vim.system(command {
      "release-agent", vim.env.HERDR_PANE_ID, "--source", SOURCE, "--agent", "nvim", "--seq", next_seq(),
    }):wait(1000)
  end)
end

--- `nvim +HerdrResume`: restaura la sesión de la carpeta cuando nvim ya arrancó
--- (si no, el dashboard se abre encima de la sesión restaurada)
function M.resume()
  local function restore()
    local session = require "utils.session"
    if session.exists() then
      session.restore()
    end
  end
  if vim.v.vim_did_enter == 1 then
    return restore()
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.schedule(restore)
    end,
  })
end

return M
