-- Tests of the Herdr integration (nvim/lua/herdr): what the panel shows, how the state is read, the setup's report.
-- Hermetic: no plugins, no config, no server, no network (nothing is asked of herdr itself).
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-herdr.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
	total = total + 1
	if not vim.deep_equal(got, want) then
		fails = fails + 1
		print("FAIL " .. name)
		print("  got:  " .. vim.inspect(got))
		print("  want: " .. vim.inspect(want))
	end
end
local function ok(name, cond)
	eq(name, cond and true or false, true)
end

-- ── the version decides what nvim may do ──────────────────────────────────────
local herdr = require "herdr"
eq("0.9 cannot take a resume command", herdr.resumable "0.9.1", false)
eq("0.9.5 can", herdr.resumable "0.9.5", true)
eq("0.10 can", herdr.resumable "0.10.0", true)
eq("0.11 can", herdr.resumable "0.11.2", true)
eq("1.0 can", herdr.resumable "1.0.0", true)

-- ── the modes ────────────────────────────────────────────────────────────────
local settings = require "core.settings"
eq("herdr is auto by default", settings.herdr.enabled, "auto")
eq("the registration is auto by default", settings.herdr.register, "auto")
eq("auto means on when the binary is there", herdr.mode(), "auto")
eq("auto is the mode", herdr.register_mode(), "auto")

settings.herdr.enabled = false
eq("off is off", herdr.mode(), "off")
settings.herdr.enabled = true
eq("on is on", herdr.mode(), "on")
settings.herdr.enabled = "auto"

settings.herdr.register = false
eq("the registration can be off", herdr.register_mode(), "off")
settings.herdr.register = true
eq("the registration can be on", herdr.register_mode(), "on")
settings.herdr.register = "auto"

-- the old knob (local.lua) still decides when it is there
settings.session.herdr = true
eq("the old knob can turn it on", herdr.register_mode(), "on")
settings.session.herdr = false
eq("and off", herdr.register_mode(), "off")
settings.session.herdr = nil
eq("and when it is not there, the new one decides", herdr.register_mode(), "auto")

-- ── what the panel shows ─────────────────────────────────────────────────────
local panel = require "herdr.panel"
local home = vim.fn.expand "~"
local agents = {
	{ agent = "opencode", agent_status = "working", cwd = home .. "/Work/leader", workspace_id = "w1" },
	{ agent = "claude", agent_status = "idle", cwd = home .. "/Docs/api", workspace_id = "w2" },
}
local workspaces = {
	{ workspace_id = "w1", label = "leader" },
	{ workspace_id = "w2", label = "api" },
}
local rows = panel.rows { agents = agents, workspaces = workspaces }
eq("a title per workspace and a row per agent", #rows, 4)
eq("the first is the title of the first workspace", rows[1].group, "leader")
eq("the second is its agent", rows[2].agent.agent, "opencode")
eq("the third is the next title", rows[3].group, "api")
eq("the fourth is its agent", rows[4].agent.agent, "claude")

local line = panel.list_line(rows[2])
eq("the state comes first", line[1][1]:gsub("%s", ""), "●")
eq("the agent is named", line[2][1], "opencode")
eq("and where it is", line[3][1]:gsub("^%s+", ""), "~/Work/leader")

local idle = panel.list_line(rows[4])
eq("an idle agent is a hollow dot", idle[1][1]:gsub("%s", ""), "○")
local blocked = panel.list_line { agent = { agent = "claude", agent_status = "blocked", cwd = "/x" } }
eq("a blocked agent says so", blocked[1][1]:gsub("%s", ""), "!")

eq("no agent, no row to rest on", #panel.rows { agents = {}, workspaces = {} }, 1)
eq("and it says so", panel.rows { agents = {}, workspaces = {} }[1].empty, true)

-- ── the setup's report ───────────────────────────────────────────────────────
local setup = require "herdr.setup"
local integrations = setup.integrations [[
pi: current (v9) (/home/saza/.pi/agent/extensions/herdr-agent-state.ts)
claude: current (v10) (/home/saza/.claude/hooks/herdr-agent-state.sh)
opencode: needs repair (v12) (/home/saza/.config/opencode/plugins/herdr-agent-state.js)
copilot: not installed (/home/saza/.copilot/hooks/herdr-agent-state.sh)
letta (experimental): not installed (/home/saza/.letta/hooks/herdr-agent-session.sh)
]]
eq("every integration is read", #integrations, 5)
eq("the name is the agent", integrations[1].name, "pi")
eq("its state", integrations[1].state, "current")
eq("and where it lives", integrations[1].path, "/home/saza/.pi/agent/extensions/herdr-agent-state.ts")
eq("a repair is a state too", integrations[3].state, "needs repair")
eq("a missing one", integrations[4].state, "not installed")
eq("an experimental name loses its parenthesis", integrations[5].name, "letta")

local lines = setup.lines {
	installed = true,
	version = "0.10.0",
	channel = "stable",
	server = "running",
	socket = "/home/saza/.config/herdr/herdr.sock",
	inside = true,
	pane = "w1:p1",
	resumable = true,
	integrations = integrations,
}
local text = table.concat(lines, "\n")
ok("the report says the version", text:find "0.10.0" ~= nil)
ok("and that the server runs", text:find "running" ~= nil)
ok("and that this nvim is inside a pane", text:find "w1:p1" ~= nil)
ok("and what the registration is", text:find "Registers as an agent" ~= nil)
ok("and the integrations of the agents it knows", text:find "Integration · claude" ~= nil)

-- ── the CLI's errors ─────────────────────────────────────────────────────────
local cli = require "herdr.cli"
eq(
	"the message of a JSON error is what is said",
	cli.error({ code = 1, stdout = "", stderr = '{"error":{"code":"agent_not_idle","message":"cannot read"}}' }, { "agent" }),
	"cannot read"
)
eq(
	"without one, what herdr said",
	cli.error({ code = 1, stdout = "", stderr = "boom" }, { "agent" }),
	"boom"
)
eq(
	"and with nothing at all, what happened",
	cli.error({ code = 2, stdout = "", stderr = "" }, { "agent" }),
	"herdr agent failed (code 2)"
)

-- a command that answers with NOTHING did its job: it is not a failure (measured: `pane report-agent` is like that)
eq("an empty answer is a success", cli.parse(""), {})
eq("and so is a blank one", cli.parse("  \n "), {})
eq("and a real answer is parsed", cli.parse '{"result":{"agents":[]}}', { result = { agents = {} } })
local bad, bad_err = cli.parse "not json at all"
eq("but something that is not JSON is a failure", bad, nil)
ok("and it says so", (bad_err or ""):find "not JSON" ~= nil)

-- ── what nvim is doing, told to herdr ────────────────────────────────────────
local events = require "agent.events"
local real_json, real_registered, real_pane = cli.json, herdr.registered, herdr.pane_id
local sent = {}
cli.json = function(args, cb)
	sent[#sent + 1] = args
	if cb then
		cb(true, {}, nil)
	end
end
herdr.registered = function()
	return true
end
herdr.pane_id = function()
	return "w1:p1"
end

local function said(args, flag)
	for i, a in ipairs(args) do
		if a == flag then
			return args[i + 1]
		end
	end
end

require("herdr.report").setup()
events.emit("job.started", { job = { action = { desc = "implement" }, target = { path = "/tmp/x.lua" } } })
eq("it says it is working", said(sent[1], "--state"), "working")
eq("and what it is doing", said(sent[1], "--message"), "implement · x.lua")
eq("in its own pane", sent[1][3], "w1:p1")
events.emit("job.settled", { job = {}, outcome = "done" })
eq("and when nothing runs, it is idle", said(sent[2], "--state"), "idle")

herdr.registered = function()
	return false
end
events.emit("job.started", { job = { action = { desc = "implement" } } })
eq("a nvim that did not register says nothing", #sent, 2)

cli.json, herdr.registered, herdr.pane_id = real_json, real_registered, real_pane

print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. "/" .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
