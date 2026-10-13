-- ── Commits (menú <leader>G): fachada ────────────────────────────────────────
-- Una sola experiencia, el panel (commit/panel.lua), con tres entradas:
--   open()   revisar lo que se commitea, escribir el mensaje (tipo/scope asistidos) y commitear
--   ai()     igual, pidiendo ya el borrador al agente (lee solo lo preparado; el panel dice qué y con qué modelo)
--   amend()  reescribir el mensaje del último commit (avisa si ya está en el remoto)
--   commit/conventional.lua  validación y sugerencias (puro) · commit/git.lua  git · commit/ai.lua  el borrador
local M = {}

function M.open()
  require("commit.panel").open()
end

function M.ai()
  require("commit.panel").open { ai = true }
end

function M.amend()
  local git = require "commit.git"
  local root = git.root()
  if not root then
    return require("utils.log").warn "Not inside a git repository"
  end
  -- reescribir un commit que otros ya pueden tener rompe su historial
  if git.head(root) and git.head_on_remote(root) then
    return vim.ui.select({ "Amend anyway (needs a force push later)", "Cancel" }, {
      prompt = "This commit is already on the remote",
    }, function(_, idx)
      if idx == 1 then
        require("commit.panel").open { amend = true }
      end
    end)
  end
  require("commit.panel").open { amend = true }
end

return M
