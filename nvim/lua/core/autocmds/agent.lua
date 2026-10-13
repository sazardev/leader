-- ── Hallazgos del agente que sobreviven a la sesión ──────────────────────────
-- Al abrir un archivo se le devuelven sus hallazgos guardados (agent/persist.lua); al guardarlo, se
-- actualizan sus posiciones. Casi gratis: sin archivo de hallazgos no hace nada.
local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("AgentFindings", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      require("agent.persist").restore(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      if package.loaded["agent.persist"] then
        require("agent.persist").resync(args.buf)
      end
    end,
  })

  -- :AgentClear [file|all]; con rango (`:'<,'>AgentClear`) o sin argumento, la línea / selección
  vim.api.nvim_create_user_command("AgentClear", function(o)
    local scope = o.args ~= "" and o.args or "line"
    if scope ~= "line" and scope ~= "file" and scope ~= "all" then
      return require("utils.log").warn "AgentClear: use file, all or nothing (line)"
    end
    local ranged = o.range > 0 and scope == "line"
    require("agent").clear(scope, ranged and o.line1 or nil, ranged and o.line2 or nil)
  end, {
    nargs = "?",
    range = true,
    complete = function()
      return { "file", "all" }
    end,
    desc = "Descarta hallazgos del agente: línea (por defecto), file o all",
  })
end

return M
