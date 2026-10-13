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
end

return M
