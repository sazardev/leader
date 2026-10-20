-- Tests of the settings panel (nvim/lua/prefs): the saved choices, the item registry, what a row shows and what Enter does.
-- Hermetic: no plugins, no config, a temp state dir.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-prefs.lua"
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

local notes = {}
package.loaded["utils.log"] = {
	info = function(m)
		notes[#notes + 1] = "info: " .. m
	end,
	warn = function(m)
		notes[#notes + 1] = "warn: " .. m
	end,
	error = function(m)
		notes[#notes + 1] = "error: " .. m
	end,
}

package.loaded["appearance"] = {
	current = function()
		return "gruvbox"
	end,
	default = function()
		return "gruvbox"
	end,
} -- needs NvChad
local store = require("prefs.store")

-- ── store: dotted paths ─────────────────────────────────────────────────────
local t = {}
store.set(t, "ui.motion", false)
store.set(t, "agent.verify.enabled", true)
eq("store: set builds the tables on the way", t, { ui = { motion = false }, agent = { verify = { enabled = true } } })
eq("store: get reads a path", { store.get(t, "agent.verify.enabled"), store.get(t, "ui.nope.deeper") }, { true, nil })
store.set(t, "ui.motion", nil)
eq("store: a nil removes it", store.get(t, "ui.motion"), nil)
eq(
	"store: nest turns the flat map into settings",
	store.nest({ ["a.b"] = 1, ["a.c"] = 2, d = 3 }),
	{ a = { b = 1, c = 2 }, d = 3 }
)

-- ── store: the file ─────────────────────────────────────────────────────────
store.clear()
eq("store: no file, no choices", store.read(), {})
store.save("ui.motion", false)
store.save("light.force", true)
eq("store: saved choices come back", store.read(), { ["ui.motion"] = false, ["light.force"] = true })
store.save("light.force", nil)
eq("store: saving nil forgets one", store.read(), { ["ui.motion"] = false })

-- ── settings: a saved choice wins, NVIM_NO_LOCAL ignores them ───────────────
package.loaded["core.settings"] = nil
eq("settings: the saved choice is applied over the default", require("core.settings").ui.motion, false)
package.loaded["core.settings"] = nil
vim.env.NVIM_NO_LOCAL = "1"
eq(
	"settings: NVIM_NO_LOCAL ignores saved choices (the cheatsheet must not depend on the machine)",
	require("core.settings").ui.motion,
	true
)
vim.env.NVIM_NO_LOCAL = nil
package.loaded["core.settings"] = nil
store.clear()
local settings = require("core.settings")
local prefs = require("prefs")

-- ── the registry ────────────────────────────────────────────────────────────
local items = prefs.items()
ok("registry: there are items", #items >= 15)
local bad, ids = {}, {}
for _, item in ipairs(items) do
	local good = type(item.group) == "string"
		and type(item.label) == "string"
		and (item.kind == "toggle" or item.kind == "choice" or item.kind == "action")
	if item.kind == "action" then
		good = good and type(item.run) == "function"
	else
		good = good and (item.id ~= nil or (item.get ~= nil and item.apply ~= nil))
		good = good and #prefs.choices(item) >= 2
	end
	if item.id then
		good = good and not ids[item.id]
		ids[item.id] = true
		-- a setting the panel writes has to exist where it writes (or be an unset default like light.force)
		good = good and (store.get(settings, item.id) ~= nil or item.id == "light.force" or item.get ~= nil)
	end
	if not good then
		bad[#bad + 1] = item.group .. "/" .. item.label
	end
end
eq("registry: every item follows the contract, ids are unique and exist", bad, {})
eq("registry: find by id", prefs.find("ui.motion").label, "Motion")

-- ── values and text ─────────────────────────────────────────────────────────
local motion = prefs.find("ui.motion")
eq("text: a toggle reads on/off", prefs.text(motion), "on")
local flash = prefs.find("ui.fresh_ms")
eq("text: a choice shows its label", prefs.text(flash), "on")
settings.ui.fresh_ms = 300
eq("text: a value outside the list is shown as it is", prefs.text(flash), "300")
settings.ui.fresh_ms = 450
local light = prefs.find("light.force")
eq("text: an unset choice reads as its nil label", prefs.text(light), "auto")

-- ── what Enter does ─────────────────────────────────────────────────────────
notes = {}
prefs.cycle(motion)
eq("cycle: a toggle flips live", settings.ui.motion, false)
eq("cycle: and is saved", store.read(), { ["ui.motion"] = false })
eq("cycle: and says so", notes, { "info: Motion: off" })
prefs.cycle(motion)
eq("cycle: back on", { settings.ui.motion, store.read()["ui.motion"] }, { true, true })

notes = {}
prefs.cycle(light) -- auto → on
eq("cycle: auto steps to on", { settings.light.force, store.read()["light.force"] }, { true, true })
eq("cycle: a restart-only setting says so", notes, { "info: Light mode: on (applies on restart)" })
prefs.cycle(light) -- on → off
prefs.cycle(light) -- off → auto
eq("cycle: back to auto forgets the saved choice", { settings.light.force, store.read()["light.force"] }, { nil, nil })

local autoread = prefs.find("options.autoread")
prefs.cycle(autoread)
eq("apply: the live effect runs", vim.o.autoread, false)
prefs.cycle(autoread)
eq("apply: and back", vim.o.autoread, true)

-- an item that owns its state (diagnostic blocks) is read and written through its owner
local state = { enabled = true }
package.loaded["utils.diagblocks"] = {
	get = function()
		return vim.deepcopy(state)
	end,
	set = function(c)
		state = vim.tbl_extend("force", state, c)
	end,
}
local inline = vim.tbl_filter(function(i)
	return i.label == "Inline blocks"
end, items)[1]
prefs.cycle(inline)
eq("owner: it goes through the owner", state.enabled, false)
eq("owner: nothing is saved by the panel", store.read()["Inline blocks"], nil)

-- a broken apply does not take the panel down
local boom = {
	group = "T",
	label = "Boom",
	kind = "toggle",
	id = "ui.motion",
	apply = function()
		error("nope")
	end,
}
notes = {}
prefs.set(boom, false)
ok("apply: a failure is reported, not thrown", notes[1] and notes[1]:find("did not apply", 1, true) ~= nil)
prefs.set(motion, true)

-- ── rows ────────────────────────────────────────────────────────────────────
local rows = prefs.rows({ motion, flash, light })
eq(
	"rows: group, label and value in aligned columns",
	rows,
	{ "Appearance  Motion           on", "Appearance  Flash on change  on", "System      Light mode       auto" }
)

-- ── the panel: a short list cycles, a long one opens a picker, an action runs ─
local picked, reopened = {}, 0
package.loaded["agent.ui.select"] = {
	pick = function(list, opts, cb)
		picked = { list = list, opts = opts, cb = cb }
	end,
}
prefs.open()
eq("panel: titled Settings", picked.opts.title, "Settings")
-- one row per item it lists (the App group only inside the desktop app)
local listed = vim.tbl_filter(function(item)
	return not item.when or item.when()
end, items)
eq("panel: one row per item", #picked.list, #listed)
eq(
	"panel: the App group stays out of a terminal",
	vim.iter(picked.list):any(function(r)
		return r.item.group == "App"
	end),
	vim.g.leader_gui == true
)
local row_of = function(label)
	for _, r in ipairs(picked.list) do
		if r.item.label == label then
			return r
		end
	end
end
local before = settings.ui.motion
picked.cb(row_of("Motion"))
eq("panel: Enter on a toggle flips it", settings.ui.motion, not before)
vim.wait(50)
eq("panel: and the list comes back on that row", picked.opts.index, row_of("Motion").at)
prefs.cycle(motion)

picked.cb(row_of("Answer language"))
eq("panel: a long choice opens a picker titled by the row", picked.opts.title, "Answer language")
eq(
	"panel: with the current value marked",
	vim.tbl_filter(function(r)
		return r.current
	end, picked.list)[1].label,
	"English"
)
picked.cb(vim.tbl_filter(function(r)
	return r.label == "Spanish"
end, picked.list)[1])
eq("panel: choosing sets it live", settings.agent.language, "Spanish")
settings.agent.language = "English"

local ran = false
local action = {
	group = "T",
	label = "Do",
	kind = "action",
	run = function()
		ran = true
	end,
}
prefs.activate(action, 1)
ok("panel: Enter on an action runs it", ran)

-- ── info ────────────────────────────────────────────────────────────────────
local lines = require("prefs.info").lines({
	version = "v1.2.0",
	root = "/home/x/cfg",
	startup_ms = 118.4,
	plugins = { loaded = 31, count = 60 },
	theme = "gruvbox",
	light = false,
	servers = { "gopls", "lua_ls" },
	saved = 2,
})
eq("info: reads like a short report", lines, {
	"# Info",
	"",
	"- **Config** v1.2.0 · /home/x/cfg",
	"- **Startup** 118 ms · 31 of 60 plugins loaded",
	"- **Theme** gruvbox",
	"- **Light mode** off",
	"- **Language servers** gopls, lua_ls",
	"- **Saved choices** 2 from the settings panel",
})
local bare = require("prefs.info").lines({ version = "unknown", theme = "x", light = true, servers = {}, saved = 0 })
eq("info: without a clone, startup or servers it still reads", { bare[3], bare[5], bare[6], bare[7] }, {
	"- **Config** unknown",
	"- **Light mode** on (no resident language servers)",
	"- **Language servers** none in this buffer",
	"- **Saved choices** none",
})

-- ── update ──────────────────────────────────────────────────────────────────
local upd = require("prefs.update")
eq(
	"update: git's own words, first line",
	upd.summary("\nerror: Your local changes would be overwritten\nPlease commit"),
	"error: Your local changes would be overwritten"
)
eq("update: nothing printed", upd.summary(""), "git printed nothing")
eq(
	"update: already current",
	{ upd.changed("Already up to date.\n"), upd.changed("Updating a..b\nFast-forward") },
	{ false, true }
)

-- ── the menu ────────────────────────────────────────────────────────────────
local menu = require("menus.settings")
eq(
	"menu: the panel and the few keys that earn their own",
	{ menu.prefix, vim.tbl_map(function(m)
		return m[1]
	end, menu.maps) },
	{ "S", { "p", "t", "f", "l", "M", "i", "u" } }
)
local fmt = vim.tbl_filter(function(m)
	return m[1] == "f"
end, menu.maps)[1]
local save_before = settings.format_on_save.enabled
fmt[3]()
eq("menu: Sf flips format on save", settings.format_on_save.enabled, not save_before)

store.clear()
print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
