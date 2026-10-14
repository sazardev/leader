-- A way back before a plan touches many files: `git stash create` makes a commit of the work tree as it is NOW without
-- changing anything (no stash entry, no reset); with a clean tree HEAD is the snapshot. Afterwards `git diff <ref>` shows
-- everything the plan changed and `git checkout <ref> -- <file>` restores a file.
local git = require "commit.git"

local M = {}

---@param root string
---@return { ref: string, short: string }?
function M.take(root)
  local out, code = git.run({ "stash", "create" }, root)
  local ref = vim.trim(out)
  if code ~= 0 or ref == "" then
    out, code = git.run({ "rev-parse", "HEAD" }, root)
    ref = vim.trim(out)
  end
  if code ~= 0 or ref == "" then
    return nil
  end
  return { ref = ref, short = ref:sub(1, 8) }
end

---@param snap { short: string }
---@return string
function M.how_to_return(snap)
  return ("snapshot %s: `git diff %s` shows what the plan changed, `git checkout %s -- <file>` restores a file"):format(
    snap.short,
    snap.short,
    snap.short
  )
end

return M
