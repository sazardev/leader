-- ── Entrega a un agente que ya corre en un pane de Herdr ─────────────────────
-- Para cuando la tarea es más grande que una acción de un disparo: se manda
-- `archivo:rango` + tu instrucción al agente que elijas (Claude Code, etc.) y el trabajo
-- sigue allí. Usa la CLI de Herdr (`herdr agent list|prompt`); solo dentro de Herdr.
local M = {}

---@return boolean
function M.available()
  return vim.env.HERDR_ENV == "1" and (vim.env.HERDR_BIN_PATH or "") ~= ""
end

---@param args string[]
---@param cb fun(out: vim.SystemCompleted)
local function herdr(args, cb)
  vim.system(vim.list_extend({ vim.env.HERDR_BIN_PATH }, args), { text = true }, function(out)
    vim.schedule(function()
      cb(out)
    end)
  end)
end

--- Agentes disponibles, los de esta carpeta primero (y sin el pane de nvim)
---@param cb fun(agents: table[])
function M.agents(cb)
  herdr({ "agent", "list" }, function(out)
    local ok, data = pcall(vim.json.decode, out.stdout or "")
    local all = ok and data.result and data.result.agents or {}
    local cwd, own = vim.fn.getcwd(), vim.env.HERDR_PANE_ID
    local list = vim.tbl_filter(function(a)
      return a.pane_id ~= own
    end, all)
    local function here(a)
      return (a.foreground_cwd or a.cwd or ""):sub(1, #cwd) == cwd and 0 or 1
    end
    table.sort(list, function(a, b)
      if here(a) ~= here(b) then
        return here(a) < here(b)
      end
      return (a.name or "") < (b.name or "")
    end)
    cb(list)
  end)
end

---@param agent table
---@return string
function M.label(agent)
  return ("%s · %s · %s · %s"):format(
    agent.name or agent.pane_id,
    agent.agent or "?",
    agent.agent_status or "?",
    vim.fn.fnamemodify(agent.foreground_cwd or agent.cwd or "", ":~")
  )
end

---@param pane_id string
---@param message string
---@param cb fun(ok: boolean, err: string?)
function M.send(pane_id, message, cb)
  herdr({ "agent", "prompt", pane_id, message }, function(out)
    cb(out.code == 0, out.code ~= 0 and (out.stderr ~= "" and out.stderr or out.stdout) or nil)
  end)
end

return M
