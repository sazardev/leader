-- The history of the target's lines: the last few commits that touched them (`git log -L`), one line each. It answers "why is
-- this like this?" and warns when the same thing was fixed before. Local and free; costs ~40 tokens per commit. Only for
-- code that is committed (a new file has no history). Opt-in per action (explain, review, refactor).
local settings = require("core.settings").agent.context

local SUBJECT_MAX = 100

--- `git log` output (`%h %as %s`, one per line) → the lines to send
---@param stdout string
---@param limit integer
---@return string[]
local function parse(stdout, limit)
  local out = {}
  for line in stdout:gmatch "[^\r\n]+" do
    if line:match "^%x+ %d%d%d%d%-%d%d%-%d%d " then
      out[#out + 1] = line:sub(1, SUBJECT_MAX + 20)
      if #out >= limit then
        break
      end
    end
  end
  return out
end

return {
  cap = 600,
  stability = 3,
  parse = parse,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local abs = vim.api.nvim_buf_get_name(target.buf)
    local root = abs ~= "" and vim.fs.root(abs, ".git") or nil
    if not root then
      return done(nil)
    end
    local rel = abs:sub(#root + 2)
    vim.system({
      "git",
      "log",
      "-n" .. settings.gitlog,
      ("-L%d,%d:%s"):format(target.first, target.last, rel),
      "--no-patch",
      "--format=%h %as %s",
    }, { cwd = root, text = true, timeout = 2000 }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          return done(nil) -- not committed yet, or the range does not exist in HEAD
        end
        local lines = parse(res.stdout or "", settings.gitlog)
        done(
          #lines > 0 and ("Recent commits that touched these lines (newest first):\n" .. table.concat(lines, "\n"))
            or nil
        )
      end)
    end)
  end,
}
