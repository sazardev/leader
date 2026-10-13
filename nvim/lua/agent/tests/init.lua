-- ── Tests with the agent (<leader>aT) ─────────────────────────────────────────
--   run(name)   write | mock | fix: LLM actions (same pipeline and experience)
--   gaps()      which functions in the folder have no test at all. Local, 0 tokens
--
--   convention.lua  where tests live, framework and how to run them      target.lua  the end of the test file
--   run.lua         run a test and clean up its output                    gaps.lua    the local analysis
--   actions/        the level's actions (own registry)
local M = {}

---@param name string "write" | "mock" | "fix"
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.tests.actions").get(name), opts)
end

function M.gaps()
  require("agent.tests.gaps").run()
end

return M
