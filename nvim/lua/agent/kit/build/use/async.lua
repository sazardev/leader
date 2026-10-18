-- ── Build with agent · use: steps that wait without blocking the editor ─────
-- Driving an app is a long chain of "run this, wait until the screen settles, look": written as straight code in a
-- coroutine, where `system` and `sleep` yield until their callback comes back (on the main loop). The build view keeps
-- redrawing meanwhile and `x` still stops the build.
local M = {}

--- Runs `fn` as a coroutine; `done(true, ...)` with what it returns, `done(false, traceback)` when it throws
---@param fn fun(): ...
---@param done fun(ok: boolean, ...)
function M.run(fn, done)
  local co = coroutine.create(fn)
  local function step(...)
    local res = vim.F.pack_len(coroutine.resume(co, ...))
    if not res[1] then
      return done(false, debug.traceback(co, tostring(res[2])))
    end
    if coroutine.status(co) == "dead" then
      return done(true, unpack(res, 2, res.n))
    end
    -- what it yielded is a function that starts the wait and calls back with what resumes it
    res[2](vim.schedule_wrap(step))
  end
  step()
end

--- Inside `run`: a command's result ({ code, stdout, stderr }); a missing program is code 127, never a throw
---@param cmd string[]
---@param opts table?
---@return { code: integer, stdout: string, stderr: string }
function M.system(cmd, opts)
  return coroutine.yield(function(resume)
    local ok, err = pcall(vim.system, cmd, vim.tbl_extend("force", { text = true }, opts or {}), function(res)
      resume { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
    end)
    if not ok then
      resume { code = 127, stdout = "", stderr = tostring(err) }
    end
  end)
end

--- Inside `run`: waits `ms`
---@param ms integer
function M.sleep(ms)
  coroutine.yield(function(resume)
    vim.defer_fn(resume, ms)
  end)
end

--- Inside `run`: polls `probe()` every `every` ms until it returns a value or `timeout` ms pass (then nil)
---@generic T
---@param probe fun(): T?
---@param timeout integer
---@param every integer?
---@return T?
function M.until_(probe, timeout, every)
  local waited = 0
  while waited <= timeout do
    local v = probe()
    if v ~= nil and v ~= false then
      return v
    end
    M.sleep(every or 100)
    waited = waited + (every or 100)
  end
  return nil
end

return M
