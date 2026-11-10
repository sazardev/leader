-- ── Git sync: push, pull and fetch from the <leader>G menu ───────────────────
-- They run in the integrated terminal (`utils/terminal.run`): credentials, SSH passphrases and hooks need a TTY, and
-- the answer stays there (`Esc` closes the window; the command keeps running). `command` is pure, so the exact line
-- (including the first push that sets the upstream) is known without a repository.
local log = require "utils.log"
local M = {}

--- The shell command for `action` on branch `b`. Pure.
--- - push: sets the upstream the first time (`-u origin <branch>`), otherwise plain `git push`;
--- - pull: only fast-forwards (`--ff-only`), so a divergent branch is reported, never merged behind your back;
--- - fetch: every remote, pruning the branches that no longer exist.
---@param action "push"|"pull"|"fetch"
---@param b { name: string, upstream: string? }
---@return string
function M.command(action, b)
  if action == "push" then
    return b.upstream and "git push" or ("git push -u origin " .. vim.fn.shellescape(b.name))
  end
  if action == "pull" then
    return b.upstream and "git pull --ff-only" or ("git pull --ff-only origin " .. vim.fn.shellescape(b.name))
  end
  return "git fetch --all --prune"
end

--- Run `action` in the terminal from the repository root.
---@param action "push"|"pull"|"fetch"
---@return boolean ran?
function M.run(action)
  local git = require "commit.git"
  local root = git.root()
  if not root then
    log.warn "Git: not inside a repository"
    return false
  end
  local b = git.branch(root)
  if action ~= "fetch" and (b.name == "" or b.name == "HEAD" or b.name == "(no commits yet)") then
    log.warn(("Git: no branch to %s (detached HEAD or no commits yet)"):format(action))
    return false
  end
  require("utils.terminal").run(M.command(action, b), root)
  return true
end

function M.push()
  return M.run "push"
end

function M.pull()
  return M.run "pull"
end

function M.fetch()
  return M.run "fetch"
end

return M
