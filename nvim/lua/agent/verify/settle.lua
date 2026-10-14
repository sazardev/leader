-- ── Waiting for the language server to settle ────────────────────────────────
-- After code is written into a buffer the LSP needs a moment to re-analyse it; its diagnostics arrive in one or several
-- `DiagnosticChanged` events. We wait until none has come for `settle_ms` (the verdict is stable) and never longer than
-- `max_wait_ms`. If NOTHING arrived in that time, we say so: there is no verdict to give (no LSP attached, or it is slow).
local M = {}

---@param buf integer
---@param opts { settle_ms: integer, max_wait_ms: integer }
---@param done fun(info: { heard: boolean })
---@return fun() cancel
function M.wait(buf, opts, done)
  local uv = vim.uv
  local started, last_event = uv.hrtime(), nil
  local group = vim.api.nvim_create_augroup(("AgentVerifySettle%d"):format(buf), { clear = true })
  local timer = assert(uv.new_timer())
  local finished = false

  local function stop()
    finished = true
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end

  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    buffer = buf,
    callback = function()
      last_event = uv.hrtime()
    end,
  })

  timer:start(
    50,
    50,
    vim.schedule_wrap(function()
      if finished then
        return
      end
      local now = uv.hrtime()
      local waited = (now - started) / 1e6
      local quiet = last_event and (now - last_event) / 1e6 or nil
      if (quiet and quiet >= opts.settle_ms) or waited >= opts.max_wait_ms then
        stop()
        done { heard = last_event ~= nil }
      end
    end)
  )
  return stop
end

return M
