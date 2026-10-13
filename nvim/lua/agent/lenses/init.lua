-- ── Lenses: single-focus reviews (<leader>aL) ─────────────────────────────────
-- security | performance | concurrency | errors | api. They come out as diagnostics (`[security]`) on the exact line, so
-- `af`/`aF` fix them. Each one discards what is not its business before spending anything (`gate`), and the
-- pattern-based ones (performance, errors, api) use the light model. Same pipeline and experience as `review`.
--   actions/    one lens per file (own registry)
local M = {}

---@param name string
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.lenses.actions").get(name), opts)
end

return M
