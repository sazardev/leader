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

---@param opts? { done: fun(ok: boolean, message: string)? } `done` hears how it ended (the updates panel)
function M.run(opts)
  local done = (opts or {}).done or function() end
  local root = vim.fs.dirname(vim.uv.fs_realpath(vim.fn.stdpath "config") or vim.fn.stdpath "config")
  if not vim.uv.fs_stat(root .. "/.git") then
    log.warn "Update: this config is not a git clone, nothing to pull"
    return done(false, "this config is not a git clone: run the installer again to update it")
  end
  log.info "Update: pulling…"
  vim.system({ "git", "-C", root, "pull", "--ff-only" }, { text = true, timeout = 60000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        local why = M.summary(res.stderr ~= "" and res.stderr or res.stdout)
        log.error("Update: git refused — " .. why)
        return done(false, "git refused: " .. why)
      end
      if not M.changed(res.stdout) then
        log.info "Update: already up to date"
        return done(true, "already up to date")
      end
      log.info "Update: pulled; restoring plugins to the lockfile (restart nvim afterwards)"
      vim.cmd "Lazy restore"
      done(true, "pulled; plugins restored to the lockfile, restart to use it")
    end)
  end)
end

return M
