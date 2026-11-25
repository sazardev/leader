-- Chat transport: one turn through any backend (claude, opencode, ollama, openai,
-- custom), streaming text + thinking, with usage. Agnostic: only the backend
-- contract (build/parser) matters; the user picked the backend/model already.
local backends = require "agent.backends"
local sandbox = require "agent.sandbox"
local settings = require("core.settings").agent

local M = {}

---@param sel table { backend, model?, effort? }
---@param req { system: string, prompt: string, action?: string }
---@param hooks { on_text?: fun(delta: string), on_think?: fun(delta: string) }
---@param cb fun(ok: boolean, text: string?, usage: table?, err: string?)
---@return vim.SystemObj? handle
---@return AgentCall? call
function M.run(sel, req, hooks, cb)
  hooks = hooks or {}
  local call
  local ok, handle = pcall(function()
    local backend = backends.get(sel.backend)
    local spec = backend.build {
      system = req.system,
      prompt = req.prompt,
      model = sel.model,
      effort = sel.effort,
      action = req.action or "chat",
    }
    local parser = backend.parser { on_think = hooks.on_think }
    -- quiet: the chat has its own single chip in the statusline (chat/status.lua);
    -- the one-shot call badge would show a second, duplicated spinner
    call = require("agent.calls").start(
      { action = "chat", label = "chat", quiet = true },
      sel.model and (sel.backend .. "/" .. sel.model)
    )
    local t0 = vim.uv.hrtime()
    -- sandbox cwd + PWD, same as one-shot runs (opencode resolves its project from PWD)
    local env = spec.cwd and vim.tbl_extend("force", { PWD = spec.cwd }, spec.env or {}) or spec.env
    if not spec.cwd then
      spec.cwd = sandbox.dir()
    end

    return vim.system(spec.cmd, {
      stdin = spec.stdin,
      cwd = spec.cwd,
      env = env,
      text = true,
      timeout = settings.chat.timeout_ms or settings.timeout_ms,
      stdout = function(_, data)
        if data then
          vim.schedule(function()
            local delta = parser.feed(data)
            if delta and hooks.on_text then
              hooks.on_text(delta)
            end
          end)
        end
      end,
    }, function(out)
      vim.schedule(function()
        local result = parser.finish(out.code, out.stderr or "")
        require("agent.calls").finish(call, result.ok)
        if call.cancelled then
          return cb(false, nil, nil, "cancelled")
        end
        local killed = out.code == 124 or out.code == 143 or out.signal == 15
        local ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
        if killed and not result.ok then
          return cb(
            false,
            nil,
            nil,
            ("timed out (%gs)"):format((settings.chat.timeout_ms or settings.timeout_ms) / 1000)
          )
        end
        if result.ok then
          local usage = result.usage or {}
          usage.ms = usage.ms or ms
          require("agent.runs").call(
            { action = "chat", system = req.system, prompt = req.prompt },
            sel,
            "done",
            usage,
            ms,
            result.text
          )
          require("agent.spend").add(usage.cost)
          cb(true, require("agent.text").trim(result.text or ""), usage, nil)
        else
          require("agent.runs").call({ action = "chat" }, sel, "error", result.usage, ms, result.err)
          cb(false, nil, result.usage, result.err or "chat error")
        end
      end)
    end)
  end)

  if not ok then
    if call then
      require("agent.calls").finish(call, false)
    end
    cb(false, nil, nil, tostring(handle))
    return nil, call
  end
  call.handle = handle
  return handle, call
end

return M
