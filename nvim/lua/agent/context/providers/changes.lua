-- The UNCOMMITTED changes of the target (git diff against HEAD, only the hunks touching its lines): what the `api`
-- lens needs to judge what breaks for whoever uses it. With no changes, the action never even asks for anything (0 tokens).
local text = require "agent.text"

local M = {}

--- Diff (without headers) of the target's lines against HEAD; nil if there are no changes there
---@param target AgentTarget
---@return string?
function M.diff(target)
  local abs = vim.api.nvim_buf_get_name(target.buf)
  if abs == "" then
    return nil
  end
  local root = vim.fs.root(abs, ".git")
  if not root then
    return nil
  end
  local res = vim
    .system({ "git", "diff", "-U1", "--no-color", "--no-ext-diff", "HEAD", "--", abs }, { cwd = root, text = true })
    :wait(2000)
  if res.code ~= 0 or (res.stdout or "") == "" then
    return nil
  end
  local out, keep = {}, false
  for _, line in ipairs(vim.split(res.stdout, "\n", { plain = true })) do
    local new_start, new_len = line:match "^@@ %-%d+,?%d* %+(%d+),?(%d*) @@"
    if new_start then
      local first = tonumber(new_start)
      local last = first + math.max((tonumber(new_len) or 1), 1) - 1
      keep = first <= target.last and target.first <= last
      if keep then
        out[#out + 1] = line
      end
    elseif
      keep and not (line:match "^diff " or line:match "^index " or line:match "^%-%-%- " or line:match "^%+%+%+ ")
    then
      out[#out + 1] = line
    end
  end
  return #out > 0 and table.concat(out, "\n") or nil
end

return {
  cap = 2500,
  stability = 3,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local diff = M.diff(target)
    done(diff and text.clip(diff, 2500) or nil)
  end,
  diff = M.diff,
}
