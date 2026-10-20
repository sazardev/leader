-- Tests of nvim/lua/recent: which files belong to a project's recent list, the per-project store and the order.
local ROOT = vim.env.AGENT_TEST_ROOT
vim.opt.rtp:prepend(ROOT .. "/nvim")
local failures = 0
local function check(name, cond, detail)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. vim.inspect(detail)) or ""))
	end
end

local list = require("recent.list")
local store = require("recent.store")

check("inside: a file of the project", list.inside("/p/a/x.lua", "/p/a"))
check("inside: a sibling folder with the same prefix is not", not list.inside("/p/ab/x.lua", "/p/a"))
check(
	"skip: git, node_modules, plugins",
	not list.recent_worthy("/p/a/.git/config") and not list.recent_worthy("/p/a/node_modules/x/index.js")
)
check("skip: a normal file is worth it", list.recent_worthy("/p/a/src/main.go"))

local function names(entries)
	return vim.tbl_map(function(e)
		return e.path
	end, entries)
end
local src = {
	store = {
		{ path = "/p/a/old.lua", at = 100 },
		{ path = "/p/a/new.lua", at = 300 },
		{ path = "/p/b/other.lua", at = 400 },
	},
	oldfiles = { "/p/a/ghost.lua", "/p/a/new.lua", "/p/c/else.lua", "/p/a/gone.lua" },
	open = { "/p/a/now.lua" },
	exists = function(p)
		return not p:find("gone")
	end,
	now = 1000,
}
check(
	"project list: open first, then newest, then oldfiles; nothing from other projects or gone, no repeats",
	vim.deep_equal(names(list.build("/p/a", src)), { "/p/a/now.lua", "/p/a/new.lua", "/p/a/old.lua", "/p/a/ghost.lua" }),
	names(list.build("/p/a", src))
)
check("every project: the others are there too", vim.tbl_contains(names(list.build(nil, src)), "/p/b/other.lua"))
src.max = 2
check("max cuts the list", #list.build("/p/a", src) == 2)

-- the store: a file is recorded under its own project, newest first, survives a restart
store.reset()
local repo = vim.fn.tempname()
vim.fn.mkdir(repo .. "/.git", "p")
vim.fn.mkdir(repo .. "/src", "p")
local elsewhere = vim.fn.tempname()
vim.fn.mkdir(elsewhere, "p")
check("a file belongs to the git project above it", store.project_of(repo .. "/src/a.lua", elsewhere) == repo)
check(
	"a file outside any project belongs to the folder you are in when inside it",
	store.project_of(elsewhere .. "/n.txt", elsewhere) == elsewhere
)
check("a file of another folder stays out of this project", store.project_of("/etc/hosts", elsewhere) ~= elsewhere)
store.record(repo, repo .. "/src/a.lua", 10)
store.record(repo, repo .. "/src/b.lua", 20)
store.record(repo, repo .. "/src/a.lua", 30)
check(
	"recorded again = moved to the top, once",
	vim.deep_equal(names(store.get(repo)), { repo .. "/src/a.lua", repo .. "/src/b.lua" }),
	store.get(repo)
)
store.forget(repo, repo .. "/src/b.lua")
check("forget", #store.get(repo) == 1)
store.save()
store.reset()
check("it survives a restart", #store.get(repo) == 1)
local f = io.open(store.FILE, "w")
f:write("[1,2]") -- someone else's file: not our table
f:close()
store.reset()
check("a file that is not a table is ignored", #store.get(repo) == 0)

print(failures == 0 and "ALL OK" or ("FAILURES: " .. failures))
vim.cmd(failures == 0 and "qa!" or "cq!")
