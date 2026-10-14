-- ── Settings: update the config ──────────────────────────────────────────────
-- `git pull --ff-only` on the clone this config runs from, then the plugins are restored to the (possibly new) lockfile.
-- Never merges, never discards: with local changes or diverged history git refuses and the reason is shown.
local log = require "utils.log"

local M = {}

--- What git printed, as the one line worth showing
---@param text string
---@return string
function M.summary(text)
  local lines = vim.tbl_filter(function(l)
    return l:match "%S"
  end, vim.split(text or "", "\n", { plain = true }))
  return lines[1] or "git printed nothing"
end

--- Did the pull bring anything?
---@param stdout string
---@return boolean
function M.changed(stdout)
  return not (stdout or ""):find("Already up to date", 1, true)
end

function M.run()
  local root = vim.fs.dirname(vim.uv.fs_realpath(vim.fn.stdpath "config") or vim.fn.stdpath "config")
  if not vim.uv.fs_stat(root .. "/.git") then
    return log.warn "Update: this config is not a git clone, nothing to pull"
  end
  log.info "Update: pulling…"
  vim.system({ "git", "-C", root, "pull", "--ff-only" }, { text = true, timeout = 60000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        return log.error("Update: git refused — " .. M.summary(res.stderr ~= "" and res.stderr or res.stdout))
      end
      if not M.changed(res.stdout) then
        return log.info "Update: already up to date"
      end
      log.info "Update: pulled; restoring plugins to the lockfile (restart nvim afterwards)"
      vim.cmd "Lazy restore"
    end)
  end)
end

return M
