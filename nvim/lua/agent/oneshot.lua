-- ── One-shot request with no target ──────────────────────────────────────────
-- What the uses that do not edit a buffer need (commit message...): same backend and
-- model as the actions (selection), but with no job, presenter or anchors; the caller
-- receives the text. Used from the facade: `require("agent").complete`.
local backends = require "agent.backends"
local calls = require "agent.calls"
local selection = require "agent.selection"
local settings = require("core.settings").agent
local text = require "agent.text"

local M = {}

---@param sel AgentSelection
---@param req { action: string, system: string, prompt: string, on_text: fun(delta: string)? }
---@param cb fun(ok: boolean, text: string, usage: table?)
---@return vim.SystemObj?
local function launch(sel, req, cb)
  local backend = backends.get(sel.backend)
  local spec = backend.build {
    system = req.system,
    prompt = req.prompt,
    model = sel.model,
    effort = req.effort or sel.effort, -- a request may ask for more (a build's fix round that made no progress)
    action = req.action,
    cache = req.cache,
  }
  local call = calls.start(req, sel.model and selection.label(sel))
  local parser = backend.parser { on_think = req.on_think } -- backends that do not stream thinking ignore it
  local t0 = vim.uv.hrtime()

  local ok, handle = pcall(vim.system, spec.cmd, {
    stdin = spec.stdin,
    cwd = spec.cwd,
    env = spec.env,
    text = true,
    timeout = req.timeout_ms or settings.timeout_ms,
    stdout = function(_, data)
      if data then
        vim.schedule(function()
          local new = parser.feed(data)
          if new and req.on_text then -- the caller watches the answer arrive (the build view types it out)
            req.on_text(new)
          end
        end)
      end
    end,
  }, function(out)
    vim.schedule(function()
      local result = parser.finish(out.code, out.stderr or "")
      calls.finish(call, result.ok)
      if call.cancelled then
        return cb(false, "cancelled")
      end
      local killed = out.code == 124 or out.code == 143 or out.signal == 15
      local ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
      if killed and not result.ok then
        return cb(false, ("timed out (%gs)"):format((req.timeout_ms or settings.timeout_ms) / 1000))
      end
      if result.ok then
        require("agent.runs").call(req, sel, "done", result.usage, ms, result.text)
        cb(true, text.trim(result.text or ""), result.usage)
      else
        require("agent.runs").call(req, sel, "error", result.usage, ms, result.err)
        cb(false, result.err or "unknown error")
      end
    end)
  end)

  if not ok then
    calls.finish(call, false)
    cb(false, tostring(handle))
    return nil
  end
  call.handle = handle
  return handle
end

--- Every one-shot call goes through the guards (the spend budget) before anything is sent, so the commit draft, the staged
--- review and plans are covered without each of them asking. Returns the process when the request starts at once; when a guard
--- has to ask first it returns nil (the answer arrives through `cb`).
--- `req.on_text(delta)`: optional, called with each piece of the answer as it streams (backends that stream)
--- `req.on_think(delta)`: optional, the model's thinking as it streams (claude), before the answer starts
--- `req.cache`: ask the backend to cache the prompt's prefix (a series of requests sharing their first part).
--- `req.preapproved`: the spend guard does not ask again (the caps still apply). `req.timeout_ms`: a longer limit for a
--- request known to answer long (a build plan)
---@param req { action: string, system: string, prompt: string, tier: "main"|"light"?, on_text: fun(delta: string)?, cache: boolean? }
---@param cb fun(ok: boolean, text: string, usage: table?)
---@return vim.SystemObj?
function M.run(req, cb)
  -- `name` lets the tier be reassigned from settings.agent.tiers (e.g. tiers = { commit = "main" })
  local sel = selection.current { name = req.action, tier = req.tier or "light" }
  if not sel then
    cb(false, "no agent backend found (install claude or opencode)")
    return nil
  end
  local handle
  local settled = false
  require("agent.guards").check({
    action = req.action,
    backend = sel.backend,
    model = sel.model,
    chars = #req.system + #req.prompt,
    preapproved = req.preapproved, -- the user already said yes to this spend (a build asks once for all of it)
  }, function()
    handle = launch(sel, req, cb)
    settled = true
  end, function()
    settled = true
    cb(false, "stopped by the spend budget")
  end)
  return settled and handle or nil
end

return M
