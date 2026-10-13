-- ── DDD: facade ──────────────────────────────────────────────────────────────
-- A feature separate from the normal agent (<leader>aD):
--   run(name)    LLM actions (implement, review, missing, ask): same pipeline and same experience, but
--                with the <ddd> section (layers, naming, related pieces, violations) and DDD rules
--   diagnose()   static analysis of the WHOLE project, no LLM (0 tokens): violations, gaps and connections
--
--   index.lua      project walk (layer, imports, types) with cache               imports.lua  imports per language
--   layers.lua     what each directory is and who may depend on whom             naming.lua   deduced naming
--   rules.lua      rules: dependencies, frameworks, names, aggregates, wiring
--   profile.lua    the compact <ddd> section for the model                       idioms.lua   one idiom per language
--   actions/       DDD actions (own registry)                                    diagnose.lua report + diagnostics
local M = {}

--- Runs a DDD action on the function under the cursor (or the visual selection)
---@param name string "implement" | "review" | "missing" | "ask"
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.ddd.actions").get(name), opts)
end

--- Static diagnosis of the whole project (free)
function M.diagnose()
  require("agent.ddd.diagnose").run()
end

--- Removes the DDD diagnosis violations from the whole project, including what was saved
function M.clear()
  require("agent.ddd.diagnose").clear()
  require("utils.log").info "Agent: DDD diagnosis cleared"
end

return M
