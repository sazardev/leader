-- ── Herdr ─────────────────────────────────────────────────────────────────────
-- Herdr is the terminal workspace that runs the coding agents. This module is what the config knows about it: the
-- binary (the one inside a pane, the one on PATH outside), the agents in the panes and what they are doing, and the
-- registration of nvim itself as an agent of the workspace.
--
--   cli.lua     how herdr is called (one place)
--   panel.lua   the breakdown: every agent, its state and its transcript (<leader>W)
--   report.lua  what nvim itself is doing, told to Herdr
--   setup.lua   what herdr is on this machine, and how to install or configure it
local cli = require "herdr.cli"
local settings = require "core.settings"

local M = {}

local SOURCE = "nvim"
local seq = 0
local registered = false
local version_cache = nil

--- `--seq` must grow between reports and between nvim runs
---@return string
local function next_seq()
  seq = seq + 1
  return tostring(os.time() * 1000 + seq)
end

--- "auto" | "on" | "off": what the user chose in the settings panel
---@return string
function M.mode()
  local v = settings.herdr.enabled
  if v == false then
    return "off"
  end
  if v == true then
    return "on"
  end
  return "auto"
end

--- Is the Herdr support on? "auto" means: on when the binary is there.
---@return boolean
function M.enabled()
  if M.mode() == "off" then
    return false
  end
  if M.mode() == "on" then
    return true
  end
  return cli.installed()
end

--- Should this nvim register itself as an agent in Herdr?
---@return string "auto"|"on"|"off"
function M.register_mode()
  local v = settings.herdr.register
  if v == false then
    return "off"
  end
  if v == true then
    return "on"
  end
  -- the OLD knob (local.lua): session = { herdr = true } (or false) wins over the new one
  if settings.session.herdr ~= nil then
    return settings.session.herdr and "on" or "off"
  end
  return "auto"
end

--- Are we running inside a Herdr pane?
---@return boolean
function M.inside()
  return cli.inside()
end

--- The pane this nvim is in
---@return string?
function M.pane_id()
  return M.inside() and vim.env.HERDR_PANE_ID or nil
end

-- ── What herdr knows ──────────────────────────────────────────────────────────

--- The agents of the workspace
---@param cb fun(agents: table[], err: string?)
function M.agents(cb)
  cli.json({ "agent", "list" }, function(ok, data, err)
    if not ok then
      return cb({}, err)
    end
    cb((data.result and data.result.agents) or {}, nil)
  end)
end

--- The workspaces of the session
---@param cb fun(workspaces: table[], err: string?)
function M.workspaces(cb)
  cli.json({ "workspace", "list" }, function(ok, data, err)
    if not ok then
      return cb({}, err)
    end
    cb((data.result and data.result.workspaces) or {}, nil)
  end)
end

--- One pane
---@param pane_id string
---@param cb fun(pane: table?, err: string?)
function M.pane(pane_id, cb)
  cli.json({ "pane", "get", pane_id }, function(ok, data, err)
    if not ok then
      return cb(nil, err)
    end
    cb((data.result and data.result.pane) or nil, nil)
  end)
end

--- The transcript of an agent's terminal (what it is doing, in its own words).
--- An agent that is working can only be read as it is drawn on screen (its history is only captured when it is idle),
--- so that is what is asked for then.
---@param target string  a pane id or an agent name
---@param cb fun(text: string?, err: string?)
function M.read(target, cb)
  local function try(source)
    cli.text({
      "agent",
      "read",
      target,
      "--source",
      source,
      "--lines",
      tostring(settings.herdr.lines),
    }, function(ok, text, err)
      if ok then
        return cb(text, nil)
      end
      if source ~= "visible" and (err or ""):find "agent_not_idle" or (err or ""):find "is working" then
        return try "visible"
      end
      cb(nil, err)
    end)
  end
  try "recent-unwrapped"
end

--- Why Herdr thinks an agent is in the state it is in (the rule that matched)
---@param target string
---@param cb fun(explain: table?, err: string?)
function M.explain(target, cb)
  cli.json({ "agent", "explain", target, "--json" }, function(ok, data, err)
    if not ok then
      return cb(nil, err)
    end
    cb(data, nil)
  end)
end

--- Brings an agent's pane to the front
---@param target string
---@param cb fun(ok: boolean, err: string?)
function M.focus(target, cb)
  cli.json({ "agent", "focus", target }, function(ok, _, err)
    cb(ok, err)
  end)
end

--- Sends a prompt to an agent that is already running in a pane
---@param target string
---@param text string
---@param cb fun(ok: boolean, err: string?)
function M.prompt(target, text, cb)
  cli.json({ "agent", "prompt", target, text }, function(ok, _, err)
    cb(ok, err)
  end)
end

--- The client and the server: version, channel, socket
---@param cb fun(status: table?, err: string?)
function M.status(cb)
  cli.json({ "status", "--json" }, function(ok, data, err)
    if not ok then
      return cb(nil, err)
    end
    cb(data, nil)
  end)
end

--- The version of herdr that is installed ("0.9.1")
---@param cb fun(version: string?)
function M.version(cb)
  if version_cache then
    return cb(version_cache)
  end
  cli.text({ "--version" }, function(ok, text)
    local version = ok and (text or ""):match "(%d+%.%d+%.%d+)" or nil
    version_cache = version
    cb(version)
  end)
end

-- ── nvim as an agent of the workspace ─────────────────────────────────────────

--- Registers this nvim in the pane, so Herdr knows it is there (and can bring it back after a server restart).
--- It never takes the pane from a real agent (Claude, Codex…) that already occupies it.
---@param cb fun(registered: boolean)?
function M.register(cb)
  local pane = M.pane_id()
  if not pane or #vim.api.nvim_list_uis() == 0 then
    -- without a UI this is a script or a test, not a person: it does not take a place in the workspace
    return cb and cb(false)
  end
  cli.json({ "pane", "get", pane }, function(ok, data)
    if not ok then
      return cb and cb(false)
    end
    local info = data.result and data.result.pane
    if info and info.agent ~= nil and info.agent ~= vim.NIL then
      return cb and cb(false) -- a real agent owns the pane: nvim does not take it
    end
    M.version(function(version)
      --- The resume command is the `--` of the CLI (herdr 0.9.5 and later). A version that does not know it answers
      --- "unknown option: --": then it is asked again without it, so a wrong guess never loses the registration.
      ---@param with_resume boolean
      local function send(with_resume)
        local args = {
          "pane",
          "report-agent",
          pane,
          "--source",
          SOURCE,
          "--agent",
          SOURCE,
          "--state",
          "idle",
          "--seq",
          next_seq(),
        }
        if with_resume then
          vim.list_extend(args, { "--", "nvim", "+HerdrResume" })
        end
        cli.json(args, function(ok2, _, err)
          if not ok2 and with_resume and (err or ""):find "unknown option" then
            return send(false)
          end
          registered = ok2
          if cb then
            cb(ok2)
          end
        end)
      end
      send(version ~= nil and M.resumable(version))
    end)
  end)
end

--- Has this nvim registered itself in Herdr? (only then does it report what it is doing)
---@return boolean
function M.registered()
  return registered
end

--- Does this herdr know the resume command of `pane report-agent`? (the `--` of the CLI: 0.9.5 and later).
--- It is only a HINT: the command is tried and dropped if this herdr refuses it, so a wrong guess is harmless.
---@param version string
---@return boolean
function M.resumable(version)
  local major, minor, patch = version:match "^(%d+)%.(%d+)%.(%d+)"
  major, minor, patch = tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
  if major > 0 then
    return true
  end
  if minor > 9 then
    return true
  end
  return minor == 9 and patch >= 5
end

--- Releases the pane: a normal `:q` must not leave it registered
function M.release()
  local pane = M.pane_id()
  if not pane then
    return
  end
  cli.sync({
    "pane",
    "release-agent",
    pane,
    "--source",
    SOURCE,
    "--agent",
    SOURCE,
    "--seq",
    next_seq(),
  })
end

--- `nvim +HerdrResume`: restores the folder's session once nvim has started
--- (otherwise the dashboard opens on top of the restored session)
function M.resume()
  local function restore()
    local session = require "utils.session"
    if session.exists() then
      session.restore()
    end
  end
  if vim.v.vim_did_enter == 1 then
    return restore()
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.schedule(restore)
    end,
  })
end

return M
