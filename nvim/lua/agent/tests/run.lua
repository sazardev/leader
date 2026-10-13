-- Runs a test (command from convention.command) and returns only the useful part of its output. No model: it is the
-- prior work of `fix`, so as not to pay tokens for fixing a test that already passes.
local M = {}

local TIMEOUT_MS = 90000
local OUTPUT_MAX = 2500

--- Strips colors and the noise of what passes, and clips
---@param raw string
---@return string
function M.clean(raw)
  local lines = {}
  for _, l in ipairs(vim.split((raw:gsub("\27%[[%d;]*m", "")), "\n", { plain = true })) do
    local noise = l:match "^%s*$"
      or l:match "^=== RUN"
      or l:match "^%-%-%- PASS"
      or l:match "^PASS$"
      or l:match "^ok%s"
      or l:match "^%s*%.+%s*%[?%s*%d*%%?%]?%s*$"
    if not noise then
      lines[#lines + 1] = l
    end
  end
  local text = table.concat(lines, "\n")
  return #text > OUTPUT_MAX and (text:sub(1, OUTPUT_MAX) .. "\n[… cut]") or text
end

---@param run AgentTestRun
---@param cb fun(ok: boolean, output: string, err: string?)  ok = the tests PASS
function M.exec(run, cb)
  if vim.fn.executable(run.cmd[1]) ~= 1 then
    return cb(false, "", ("`%s` is not installed"):format(run.cmd[1]))
  end
  vim.system(run.cmd, { cwd = run.cwd, text = true, timeout = TIMEOUT_MS }, function(res)
    vim.schedule(function()
      local timed_out = res.signal == 15 or res.code == 124
      if timed_out then
        return cb(false, "", ("timed out (%ds)"):format(TIMEOUT_MS / 1000))
      end
      cb(res.code == 0, M.clean((res.stdout or "") .. "\n" .. (res.stderr or "")))
    end)
  end)
end

return M
