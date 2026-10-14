-- ── Backend: OpenCode (`opencode run`) ───────────────────────────────────────
-- opencode has no --system-prompt: the action travels as an ephemeral agent defined
-- in OPENCODE_CONFIG_CONTENT (prompt = the action, all tools turned off).
-- With `settings.agent.opencode.agent` you use your own agent and the instructions go in
-- the message; with `attach` an `opencode serve` is reused (without paying the startup), and with `serve`
-- a private one is managed and spoken to over HTTP (opencode_server.lua: ~1.5 s per action instead of ~8 s). Your global MCP servers are turned off for these runs
-- (`settings.mcp = true` keeps them): their tool schemas were ~20k input tokens and ~2 s per action.
-- Runs in the neutral directory (agent/sandbox) so the repo's AGENTS.md is not loaded.
local settings = require("core.settings").agent.opencode
local ndjson = require "agent.backends.ndjson"
local sandbox = require "agent.sandbox"
local server = require "agent.backends.opencode_server"
local text = require "agent.text"

local M = {
  name = "opencode",
  label = "OpenCode",
  default_model = settings.model,
}

-- opencode tools: all off. It is a text action, not an agent that edits.
local TOOLS = {
  bash = false,
  edit = false,
  write = false,
  read = false,
  grep = false,
  glob = false,
  list = false,
  patch = false,
  todowrite = false,
  todoread = false,
  webfetch = false,
  task = false,
  skill = false,
} -- stylua: ignore
local PERMISSIONS = { edit = "deny", bash = "deny", webfetch = "deny" }

---@return boolean
function M.available()
  return vim.fn.executable "opencode" == 1
end

---@type table[]?
local cached

---@param cb fun(models: table[])
function M.models(cb)
  if settings.models then
    return cb(vim.tbl_map(function(id)
      return { id = id }
    end, settings.models))
  end
  if cached then
    return cb(cached)
  end
  vim.system({ "opencode", "models" }, { text = true }, function(out)
    vim.schedule(function()
      local list = {}
      for line in (out.stdout or ""):gmatch "[^\r\n]+" do
        if line:match "^[%w%-%._]+/%S+$" then
          list[#list + 1] = { id = line }
        end
      end
      cached = list
      cb(list)
    end)
  end)
end

--- Names of the MCP servers in the user's global opencode config. Inline config merges over it, so
--- turning them off needs their names. Tolerant of JSONC (comments, trailing commas); `{}` if unreadable.
---@return string[]
local function global_mcp_names()
  local dir = (vim.env.XDG_CONFIG_HOME or vim.fn.expand "~/.config") .. "/opencode"
  for _, file in ipairs { "opencode.jsonc", "opencode.json" } do
    local f = io.open(dir .. "/" .. file, "r")
    if f then
      local raw = f:read "*a"
      f:close()
      -- a `//` comment starts at the line start or after whitespace (the `//` of `https://` follows a colon)
      raw = raw:gsub("/%*.-%*/", ""):gsub("%s//[^\n]*", ""):gsub("^//[^\n]*", ""):gsub(",(%s*[}%]])", "%1")
      local ok, cfg = pcall(vim.json.decode, raw)
      if ok and type(cfg) == "table" and type(cfg.mcp) == "table" then
        return vim.tbl_keys(cfg.mcp)
      end
    end
  end
  return {}
end

--- Config the process receives: the agents plus, unless `settings.mcp`, every global MCP server disabled
---@param agents table?
---@return table?
function M.config(agents)
  local cfg = { agent = agents }
  if not settings.mcp then
    local mcp = {}
    for _, name in ipairs(global_mcp_names()) do
      mcp[name] = { enabled = false }
    end
    if next(mcp) then
      cfg.mcp = mcp
    end
  end
  return next(cfg) and cfg or nil
end

local NO_THINKING = { thinking = { type = "disabled" } }

---@param model string
---@return boolean
local function thinking_off(model)
  for _, pat in ipairs(settings.no_thinking or {}) do
    if model:find(pat, 1, true) then
      return true
    end
  end
  return false
end

--- Config of the private server: ONE generic tool-less agent (the action travels in the message), plus
--- a copy with thinking off for the models that accept it
---@return table
local function server_config()
  local base = {
    description = "Inline nvim agent",
    mode = "primary",
    prompt = "You are a code-editing endpoint inside an editor. Follow the <instructions> block of the message exactly.",
    tools = TOOLS,
    permission = PERMISSIONS,
  }
  return M.config {
    [server.AGENT] = base,
    [server.AGENT_FAST] = vim.tbl_extend("force", base, { options = NO_THINKING }),
  }
end

--- Starts the private server in the background (no-op if it is running, disabled or light mode)
function M.warm()
  if server.enabled(settings) and M.available() then
    server.start(server_config())
  end
end

---@param req table
---@return table
function M.build(req)
  local own_agent = settings.agent
  local agent = own_agent or ("nvim-" .. req.action)
  local prompt, env = req.prompt, nil

  M.warm()
  local provider, model = req.model:match "^([^/]+)/(.+)$"
  local warm = not own_agent
    and provider
    and server.post {
      agent = thinking_off(req.model) and server.AGENT_FAST or server.AGENT,
      model = { providerID = provider, modelID = model },
      variant = req.effort,
      parts = { { type = "text", text = ("<instructions>\n%s\n</instructions>\n\n%s"):format(req.system, req.prompt) } },
    }
  if warm then
    return warm
  end

  if own_agent or settings.attach then
    -- no inline config: the agent already exists; the instructions go in the message
    prompt = ("<instructions>\n%s\n</instructions>\n\n%s"):format(req.system, req.prompt)
    agent = own_agent or "plan" -- `plan` does not edit: safety net if there is no own agent
    local cfg = not settings.attach and M.config()
    env = cfg and { OPENCODE_CONFIG_CONTENT = vim.json.encode(cfg) } or nil
  else
    env = {
      OPENCODE_CONFIG_CONTENT = vim.json.encode(M.config {
        [agent] = {
          description = "Inline nvim agent (" .. req.action .. ")",
          mode = "primary",
          prompt = req.system,
          tools = TOOLS,
          permission = PERMISSIONS,
          options = thinking_off(req.model) and NO_THINKING or nil,
        },
      }),
    }
  end

  local cmd = {
    "opencode",
    "run",
    "--pure",
    "--format",
    "json",
    "--title",
    "nvim " .. req.action,
    "-m",
    req.model,
    "--agent",
    agent,
  }
  if settings.attach then
    vim.list_extend(cmd, { "--attach", settings.attach })
  end
  if req.effort then
    vim.list_extend(cmd, { "--variant", req.effort })
  end
  vim.list_extend(cmd, { "--", prompt })
  return { cmd = cmd, env = env, cwd = sandbox.dir() }
end

---@return table
function M.parser()
  local parts, order, err = {}, {}, nil
  local tokens_in, tokens_out, cost, cache_read, cache_write = 0, 0, 0, 0, 0

  local raw = {} -- the HTTP route answers ONE json object without a trailing newline: NDJSON never sees it

  --- Usage of a step (`run --format json` step_finish part, or the HTTP message's `info`)
  local function add_usage(t, c)
    t = type(t) == "table" and t or {}
    local cache = type(t.cache) == "table" and t.cache or {}
    cache_read = cache_read + (cache.read or 0)
    cache_write = cache_write + (cache.write or 0)
    tokens_in = tokens_in + (t.input or 0) + (cache.read or 0) + (cache.write or 0)
    tokens_out = tokens_out + (t.output or 0)
    cost = cost + (type(c) == "number" and c or 0)
  end

  --- Whole message from the server's HTTP API (or its error object)
  local function whole(msg)
    if type(msg.parts) == "table" then
      for i, p in ipairs(msg.parts) do
        if p.type == "text" and type(p.text) == "string" then
          order[#order + 1] = tostring(i)
          parts[tostring(i)] = p.text
        end
      end
      local info = type(msg.info) == "table" and msg.info or {}
      add_usage(info.tokens, info.cost)
      if type(info.error) == "table" then
        local data = info.error.data
        err = (type(data) == "table" and data.message) or info.error.name or "OpenCode error"
      end
    elseif type(msg.data) == "table" or msg.name then
      local data = type(msg.data) == "table" and msg.data or {}
      err = ((data.message or msg.name) .. (data.ref and (" (" .. data.ref .. ")") or ""))
    end
  end

  local ndfeed = ndjson.new(function(ev)
    local part = ev.part or {}
    if ev.type == "text" and type(part.text) == "string" then
      local key = part.id or tostring(#order + 1)
      local before = parts[key]
      if not before then
        order[#order + 1] = key
      end
      parts[key] = part.text
      -- a part's text may arrive whole or growing: only the new part is emitted
      if before and part.text:sub(1, #before) == before then
        return part.text:sub(#before + 1)
      end
      return part.text
    elseif ev.type == "step_finish" then
      add_usage(part.tokens, part.cost)
    elseif ev.type == "error" then
      local e = ev.error or {}
      err = (e.data and e.data.message) or e.name or "OpenCode error"
    end
  end)

  local function feed(chunk)
    raw[#raw + 1] = chunk
    return ndfeed(chunk)
  end

  return {
    feed = feed,
    finish = function(code, stderr)
      if #order == 0 and not err and #raw > 0 then
        local ok, msg = pcall(vim.json.decode, table.concat(raw))
        if ok and type(msg) == "table" then
          whole(msg)
        end
      end
      if err then
        return { ok = false, err = err }
      end
      -- if opencode cannot find the agent, it warns and carries on with the default one (which DOES have
      -- tools): that response is not the requested action, so it is treated as a failure
      local missing = stderr:match 'agent "([^"]+)" not found'
      if missing then
        return {
          ok = false,
          err = ("opencode could not find the agent '%s' (settings.agent.opencode.agent?)"):format(missing),
        }
      end
      local pieces = {}
      for _, key in ipairs(order) do
        pieces[#pieces + 1] = parts[key]
      end
      local body = table.concat(pieces, "\n")
      if body == "" then
        local msg = text.trim(stderr)
        return {
          ok = false,
          err = msg ~= "" and msg or (code ~= 0 and ("opencode exited with code %d"):format(code) or "empty response"),
        }
      end
      return {
        ok = true,
        text = body,
        usage = {
          tokens_in = tokens_in,
          tokens_out = tokens_out,
          cache_read = cache_read,
          cache_write = cache_write,
          cost = cost > 0 and cost or nil,
        },
      }
    end,
  }
end

return M
