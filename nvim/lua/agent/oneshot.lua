-- ── Petición de un disparo sin objetivo ──────────────────────────────────────
-- Lo que necesitan los usos que no editan un buffer (mensaje de commit...): mismo backend y
-- modelo que las acciones (selection), pero sin trabajo, presentador ni anclas; el llamador
-- recibe el texto. Se usa desde la fachada: `require("agent").complete`.
local backends = require "agent.backends"
local selection = require "agent.selection"
local settings = require("core.settings").agent
local text = require "agent.text"

local M = {}

---@param req { action: string, system: string, prompt: string, tier: "main"|"light"? }
---@param cb fun(ok: boolean, text: string)
---@return vim.SystemObj?
function M.run(req, cb)
  -- `name` permite reasignar el tier desde settings.agent.tiers (p. ej. tiers = { commit = "main" })
  local sel = selection.current { name = req.action, tier = req.tier or "light" }
  if not sel then
    cb(false, "no agent backend found (install claude or opencode)")
    return nil
  end

  local backend = backends.get(sel.backend)
  local spec = backend.build {
    system = req.system,
    prompt = req.prompt,
    model = sel.model,
    effort = sel.effort,
    action = req.action,
  }
  local parser = backend.parser()

  local ok, handle = pcall(vim.system, spec.cmd, {
    stdin = spec.stdin,
    cwd = spec.cwd,
    env = spec.env,
    text = true,
    timeout = settings.timeout_ms,
    stdout = function(_, data)
      if data then
        vim.schedule(function()
          parser.feed(data)
        end)
      end
    end,
  }, function(out)
    vim.schedule(function()
      local result = parser.finish(out.code, out.stderr or "")
      local killed = out.code == 124 or out.code == 143 or out.signal == 15
      if killed and not result.ok then
        return cb(false, ("timed out (%gs)"):format(settings.timeout_ms / 1000))
      end
      if result.ok then
        cb(true, text.trim(result.text or ""))
      else
        cb(false, result.err or "unknown error")
      end
    end)
  end)

  if not ok then
    cb(false, tostring(handle))
    return nil
  end
  return handle
end

return M
