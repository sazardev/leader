-- ── Update target: the config (this clone) ───────────────────────────────────
-- A target says what is installed, what is newest and how to bring it up to date. Adding one = a file here + its name
-- in `update.TARGETS`. This one is the config's git clone: `git pull --ff-only` and the plugins restored to the lockfile.
local semver = require "update.semver"

local M = { id = "config", label = "Leader config" }

---@return string? root the clone the config runs from
function M.root()
  return vim.fs.dirname(vim.uv.fs_realpath(vim.fn.stdpath "config") or vim.fn.stdpath "config")
end

---@return string?
function M.current()
  local f = io.open((M.root() or "") .. "/VERSION")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return semver.parse(text) and semver.clean(text) or nil
end

---@param info UpdateInfo
---@return string?
function M.latest(info)
  return info.version
end

---@param info UpdateInfo
---@param done fun(ok: boolean, message: string)
function M.apply(info, done)
  require("prefs.update").run { done = done }
end

return M
