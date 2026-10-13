-- ── Git info (for the dashboard) ─────────────────────────────────────────────
local M = {}

---@param args string[]
---@return string
local function git(args)
  local ok, res = pcall(function()
    return vim.system(vim.list_extend({ "git" }, args), { text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    return ""
  end
  return vim.trim(res.stdout or "")
end

---@return { repo: string, branch: string, user: string }
function M.info()
  local top = git { "rev-parse", "--show-toplevel" }
  return {
    repo = top ~= "" and vim.fn.fnamemodify(top, ":t") or "",
    branch = git { "branch", "--show-current" },
    user = git { "config", "user.name" },
  }
end

return M
