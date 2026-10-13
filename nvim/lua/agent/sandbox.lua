-- ── Directorio de trabajo neutro ─────────────────────────────────────────────
-- Los CLIs corren aquí y no en tu proyecto: así no cargan AGENTS.md/CLAUDE.md ni
-- indexan el repo (tokens y latencia), y no pueden tocar tus archivos. Todo el
-- contexto que ven lo decide agent/context, no el CLI.
local M = {}

---@type string?
local dir

---@return string
function M.dir()
  if not dir then
    dir = vim.fn.stdpath "cache" .. "/agent"
    vim.fn.mkdir(dir, "p")
  end
  return dir
end

return M
