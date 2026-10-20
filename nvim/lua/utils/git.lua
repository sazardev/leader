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

local TTL_MS = 3000
---@type table<string, { at: number, info: table }>
local cache = {}

--- Three git processes, so the start screen (which draws again on every resize) asks at most once every few seconds
---@return { repo: string, branch: string, user: string }
function M.info()
  local cwd = vim.uv.cwd() or ""
  local now = vim.uv.hrtime() / 1e6
  local hit = cache[cwd]
  if hit and now - hit.at < TTL_MS then
    return hit.info
  end
  local top = git { "rev-parse", "--show-toplevel" }
  local info = {
    repo = top ~= "" and vim.fn.fnamemodify(top, ":t") or "",
    branch = git { "branch", "--show-current" },
    user = git { "config", "user.name" },
  }
  cache[cwd] = { at = now, info = info }
  return info
end

return M
