-- ── Backend: OpenCode (`opencode run`) ───────────────────────────────────────
-- opencode has no --system-prompt: the action travels as an ephemeral agent defined
-- in OPENCODE_CONFIG_CONTENT (prompt = the action, all tools turned off).
-- With `settings.agent.opencode.agent` you use your own agent and the instructions go in
-- the message; with `attach` an `opencode serve` is reused (without paying the startup).
-- Runs in the neutral directory (agent/sandbox) so the repo's AGENTS.md is not loaded.
local settings = require("core.settings").agent.opencode
local ndjson = require "agent.backends.ndjson"
local sandbox = require "agent.sandbox"
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

---@param req table
---@return table
function M.build(req)
  local own_agent = settings.agent
  local agent = own_agent or ("nvim-" .. req.action)
  local prompt, env = req.prompt, nil

  if own_agent or settings.attach then
    -- no inline config: the agent already exists; the instructions go in the message
    prompt = ("<instructions>\n%s\n</instructions>\n\n%s"):format(req.system, req.prompt)
    agent = own_agent or "plan" -- `plan` does not edit: safety net if there is no own agent
  else
    env = {
      OPENCODE_CONFIG_CONTENT = vim.json.encode {
        agent = {
          [agent] = {
            description = "Inline nvim agent (" .. req.action .. ")",
            mode = "primary",
            prompt = req.system,
            tools = TOOLS,
            permission = PERMISSIONS,
          },
        },
      },
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

  local feed = ndjson.new(function(ev)
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
      local t = part.tokens or {}
      cache_read = cache_read + ((t.cache or {}).read or 0)
      cache_write = cache_write + ((t.cache or {}).write or 0)
      tokens_in = tokens_in + (t.input or 0) + ((t.cache or {}).read or 0) + ((t.cache or {}).write or 0)
      tokens_out = tokens_out + (t.output or 0)
      cost = cost + (part.cost or 0)
    elseif ev.type == "error" then
      local e = ev.error or {}
      err = (e.data and e.data.message) or e.name or "OpenCode error"
    end
  end)

  return {
    feed = feed,
    finish = function(code, stderr)
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
