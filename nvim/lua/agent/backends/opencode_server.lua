-- ── OpenCode: warm private server ────────────────────────────────────────────
-- `opencode run` boots the whole runtime on every call (~2.5 s) before the model starts. Here a private
-- `opencode serve` (free loopback port, random password, tool-less agent, no MCP) is started in the
-- background and actions POST straight to its HTTP API with curl (`opencode run --attach` printed no text
-- in v1.19). A message needs a fresh session (history would pile up otherwise), so one is kept created
-- ahead. It never blocks: until a session is ready, `post()` returns nil and the backend uses the cold
-- path. Stopped when Neovim exits; skipped in light mode (resident process).
local sandbox = require "agent.sandbox"

local M = {}

M.AGENT = "nvim"
M.AGENT_FAST = "nvim-fast" -- same, with thinking off (models listed in `settings.no_thinking`)

---@class OpencodeServerState
---@field job vim.SystemObj?
---@field url string?
---@field password string?
---@field starting boolean
---@field filling boolean
---@field sessions string[] sessions created ahead of use

---@return OpencodeServerState
local function fresh()
  return { starting = false, filling = false, sessions = {} }
end

local state = fresh()

---@return integer? port
local function free_port()
  local tcp = vim.uv.new_tcp()
  if not tcp then
    return nil
  end
  local ok = tcp:bind("127.0.0.1", 0)
  local addr = ok and tcp:getsockname()
  tcp:close()
  return addr and addr.port or nil
end

---@return string
local function random_secret()
  local bytes = vim.uv.random(16)
  return (bytes:gsub(".", function(c)
    return ("%02x"):format(c:byte())
  end))
end

--- Is there a server worth starting? (installed, enabled, not light mode)
---@param settings table settings.agent.opencode
---@return boolean
function M.enabled(settings)
  return settings.serve == true and not settings.attach and not require("core.light").enabled
end

---@param path string
---@param body string JSON
---@return table spec for vim.system (cmd + stdin)
local function curl(path, body)
  return {
    cmd = {
      "curl",
      "-sS",
      "-X",
      "POST",
      "-u",
      "opencode:" .. state.password,
      "-H",
      "content-type: application/json",
      "--data-binary",
      "@-",
      state.url .. path,
    },
    stdin = body,
  }
end

--- Keeps ONE session created ahead (a message needs a fresh one; reusing would drag the history along)
local function refill()
  if not state.url or state.filling or #state.sessions > 0 then
    return
  end
  state.filling = true
  local mine = state
  local spec = curl("/session", vim.json.encode { title = "nvim agent" })
  pcall(vim.system, spec.cmd, { stdin = spec.stdin, text = true }, function(out)
    mine.filling = false
    local ok, obj = pcall(vim.json.decode, out.stdout or "")
    if ok and type(obj) == "table" and type(obj.id) == "string" then
      mine.sessions[#mine.sessions + 1] = obj.id
    end
  end)
end

---@param config table OPENCODE_CONFIG_CONTENT for the server
function M.start(config)
  if state.job or state.starting then
    return
  end
  local port = free_port()
  if not port then
    return
  end
  local mine = state
  mine.starting, mine.password = true, random_secret()
  local url = ("http://127.0.0.1:%d"):format(port)
  local ok, job = pcall(vim.system, {
    "opencode",
    "serve",
    "--pure",
    "--hostname",
    "127.0.0.1",
    "--port",
    tostring(port),
  }, {
    cwd = sandbox.dir(),
    env = {
      PWD = sandbox.dir(), -- see runner.lua: `cwd` alone does not keep opencode out of the repo's AGENTS.md
      OPENCODE_CONFIG_CONTENT = vim.json.encode(config),
      OPENCODE_SERVER_PASSWORD = mine.password,
    },
    text = true,
    stdout = function(_, data)
      if data and data:find("listening on", 1, true) then
        mine.url, mine.starting = url, false
        refill()
      end
    end,
    stderr = false,
  }, function()
    -- the process ended (crash, killed): the next action starts it again
    if state == mine then
      state = fresh()
    end
  end)
  if ok then
    mine.job = job
  else
    state = fresh()
  end
end

--- Request for the server's message endpoint, on a session created ahead. nil while the server boots
--- (or has no session ready): the caller falls back to the cold path.
---@param body table message body (agent, model, parts, variant?)
---@return table? spec { cmd, stdin, cwd }
function M.post(body)
  local id = state.url and table.remove(state.sessions, 1)
  if not id then
    return nil
  end
  refill() -- the next action's session, while this one runs
  local spec = curl(("/session/%s/message"):format(id), vim.json.encode(body))
  spec.cwd = sandbox.dir()
  return spec
end

function M.stop()
  local job = state.job
  state = fresh()
  if job then
    pcall(job.kill, job, 15)
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.stop })

return M
