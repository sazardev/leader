-- ── Herdr setup ───────────────────────────────────────────────────────────────
-- What herdr is on this machine (the binary, its version, the server, whether nvim is inside a pane, the integrations
-- the agents have) and the things that can be done about it: install the binary, install an agent's integration, turn
-- the registration on or off. Nothing is installed without the user pressing the button.
local cli = require "herdr.cli"
local herdr = require "herdr"
local log = require "utils.log"

local M = {}

--- The agents whose integration herdr can install (the ones this config drives)
local AGENTS = { "claude", "opencode", "codex" }

---@class HerdrFacts
---@field installed boolean
---@field version string?
---@field inside boolean
---@field pane string?
---@field server string?      "running" | "stopped" | nil
---@field socket string?
---@field channel string?
---@field resumable boolean   this herdr can bring an agent pane back (0.10.0 and later)
---@field integrations { name: string, state: string, path: string? }[]

--- The facts of this machine
---@param cb fun(facts: HerdrFacts)
function M.facts(cb)
  local facts = {
    installed = cli.installed(),
    inside = cli.inside(),
    pane = vim.env.HERDR_PANE_ID,
    version = nil,
    server = nil,
    resumable = false,
    integrations = {},
  }
  if not facts.installed then
    return cb(facts)
  end
  herdr.version(function(version)
    facts.version = version
    facts.resumable = version ~= nil and herdr.resumable(version)
    herdr.status(function(status)
      if status then
        facts.server = status.server and status.server.status or nil
        facts.socket = status.server and status.server.socket or nil
        facts.channel = status.client and status.client.channel or nil
      end
      cli.text({ "integration", "status" }, function(_, out)
        facts.integrations = M.integrations(out or "")
        cb(facts)
      end)
    end)
  end)
end

--- The integrations herdr knows about: "opencode: needs repair (v12) (path)"
---@param out string
---@return { name: string, state: string, path: string? }[]
function M.integrations(out)
  local list = {}
  for line in out:gmatch "[^\r\n]+" do
    local name, rest = line:match "^(.-):%s*(.+)$"
    if name and name ~= "" then
      name = name:gsub("%s*%b()$", "")
      local state = rest:match "^(.-)%s*%("
      local path = rest:match "%(([^)]*)%)%s*$"
      list[#list + 1] = { name = name, state = state or rest, path = path }
    end
  end
  return list
end

--- The command that installs herdr on this machine (the one herdr updates itself)
---@return string
function M.install_command()
  if vim.fn.has "win32" == 1 or vim.fn.has "win64" == 1 then
    return 'powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"'
  end
  return "curl -fsSL https://herdr.dev/install.sh | sh"
end

--- Runs the installer in a floating terminal above the editor (sudo asks there)
---@param cmd string
function M.install(cmd)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = 3,
    col = 3,
    width = math.max(vim.o.columns - 6, 40),
    height = math.max(vim.o.lines - 8, 10),
    style = "minimal",
    border = require("ui.flat").border(),
    title = " Herdr · installing ",
    zindex = 250,
  })
  vim.fn.jobstart({ "sh", "-c", "printf '\\033[1m$ %s\\033[0m\\n\\n' \"$0\"; " .. cmd, cmd }, {
    term = true,
    on_exit = vim.schedule_wrap(function(_, code)
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if code == 0 then
        log.info "Herdr: installed — open the panel again"
      else
        log.warn(("Herdr: the installer failed (code %d)"):format(code))
      end
    end),
  })
end

--- Installs (or repairs) the integration of an agent, so it reports its own state to herdr
---@param name string
function M.install_integration(name)
  cli.json({ "integration", "install", name }, function(ok, _, err)
    log.info(ok and ("Herdr: the %s integration is installed"):format(name) or ("Herdr: " .. (err or "it failed")))
  end)
end

--- The text of the report (pure over the facts)
---@param facts HerdrFacts
---@return string[]
function M.lines(facts)
  local function row(label, value)
    return ("- **%s** %s"):format(label, value)
  end
  local lines = { "# Herdr", "" }
  if not facts.installed then
    lines[#lines + 1] = row("Installed", "no")
    lines[#lines + 1] = row("Install", M.install_command())
    return lines
  end
  lines[#lines + 1] = row("Version", (facts.version or "?") .. (facts.channel and (" · " .. facts.channel) or ""))
  lines[#lines + 1] = row("Server", facts.server or "not running")
  if facts.socket then
    lines[#lines + 1] = row("Socket", facts.socket)
  end
  lines[#lines + 1] = row("This nvim", facts.inside and ("inside a pane (" .. (facts.pane or "?") .. ")") or "outside Herdr")
  lines[#lines + 1] = row(
    "Registers as an agent",
    herdr.register_mode() .. (facts.resumable and "" or " (this herdr takes no resume command: it cannot bring the pane back)")
  )
  for _, it in ipairs(facts.integrations) do
    if vim.tbl_contains(AGENTS, it.name) then
      lines[#lines + 1] = row("Integration · " .. it.name, it.state)
    end
  end
  return lines
end

--- Opens the setup: the state of herdr on this machine and what to do about it
function M.open()
  M.facts(function(facts)
    local items = {}
    local function add(label, run)
      items[#items + 1] = { label = label, run = run }
    end
    if not facts.installed then
      add("Install Herdr  (" .. M.install_command() .. ")", function()
        M.install(M.install_command())
      end)
    end
    add("Register this nvim as an agent: " .. herdr.register_mode(), function()
      local prefs = require "prefs"
      local item = prefs.find "herdr.register"
      if item then
        prefs.cycle(item)
      end
    end)
    for _, it in ipairs(facts.integrations) do
      if vim.tbl_contains(AGENTS, it.name) and it.state ~= "current" then
        add(("Install the %s integration  (%s)"):format(it.name, it.state), function()
          M.install_integration(it.name)
        end)
      end
    end
    add("Show the report", function()
      require("agent.ui.panel").open(M.lines(facts), "Herdr · setup")
    end)
    require("agent.ui.select").pick(items, { title = "Herdr · setup" }, function(choice)
      choice.run()
    end)
  end)
end

return M
