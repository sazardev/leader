-- ── Neutral working directory ────────────────────────────────────────────────
-- The CLIs run here and not in your project: that way they do not load AGENTS.md/CLAUDE.md nor
-- index the repo (tokens and latency), and they cannot touch your files. All the
-- context they see is decided by agent/context, not by the CLI.
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
