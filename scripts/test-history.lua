-- Tests of the editing history (nvim/lua/history): the pure helpers here, the keys in a child nvim typed one key at a
-- time (nvim_input), so undo steps, `.`, macros and the clipboard behave as with a person at the keyboard.
--   nvim -u NONE --headless -c "luafile scripts/test-history.lua"
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

-- ── pure helpers ────────────────────────────────────────────────────────────
local undo = require("history.undo")
eq("boundary: after a space", undo.boundary(" ", 3, 3), true)
eq("boundary: after a tab", undo.boundary("\t", 3, 3), true)
eq("boundary: inside a word", undo.boundary("a", 3, 3), false)
eq("boundary: start of the line", undo.boundary("", 3, 3), false)
eq("boundary: a new line", undo.boundary("a", 4, 3), true)

local yanks = require("history.yanks")
local function e(text, t)
	return { lines = vim.split(text, "\n"), type = t or "v", time = 0 }
end
local function texts(list)
	return vim.tbl_map(function(x)
		return table.concat(x.lines, "\n")
	end, list)
end
eq("push: newest first", texts(yanks.push({ e("a") }, e("b"), 5)), { "b", "a" })
eq("push: a repeated text moves up", texts(yanks.push({ e("a"), e("b") }, e("b"), 5)), { "b", "a" })
eq("push: capped", texts(yanks.push({ e("a"), e("b") }, e("c"), 2)), { "c", "a" })
eq("push: blank texts are skipped", texts(yanks.push({ e("a") }, e("  \n"), 5)), { "a" })
eq("push: too long is skipped", texts(yanks.push({ e("a") }, e("abcdef"), 5, 3)), { "a" })
eq("find: by text", yanks.find({ e("a"), e("b\nc") }, { "b", "c" }), 2)
eq("find: missing", yanks.find({ e("a") }, { "z" }), nil)
eq("label: first line and the rest", yanks.label(e("\n  func main() {\n}\n")), "func main() {  (+3 lines)")
eq("label: one line", yanks.label(e("word")), "word")

-- ── the keys, in a child nvim ───────────────────────────────────────────────
local init = ([[
vim.opt.rtp:prepend(%q)
package.path = %q .. "/lua/?.lua;" .. %q .. "/lua/?/init.lua;" .. package.path
vim.o.clipboard = ""
require("history").setup()
]]):format(root .. "/nvim", root .. "/nvim", root .. "/nvim")
local initfile = vim.fn.tempname() .. ".lua"
vim.fn.writefile(vim.split(init, "\n"), initfile)

local function child()
	local ch = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", initfile, "-i", "NONE", "-n" }, { rpc = true })
	local c = {}
	function c.keys(keys)
		for _, k in ipairs(vim.split(vim.keycode(keys), "")) do
			vim.rpcrequest(ch, "nvim_input", k == "<" and "<lt>" or k)
			vim.wait(4)
		end
		vim.wait(40)
	end
	function c.lua(code, ...)
		return vim.rpcrequest(ch, "nvim_exec_lua", code, { ... })
	end
	function c.line()
		return vim.rpcrequest(ch, "nvim_get_current_line")
	end
	function c.lines()
		return vim.rpcrequest(ch, "nvim_buf_get_lines", 0, 0, -1, false)
	end
	function c.stop()
		vim.fn.jobstop(ch)
	end
	return c
end

local c = child()
c.keys("ione two three<Esc>")
local steps = { c.line() }
for _ = 1, 3 do
	c.keys("u")
	steps[#steps + 1] = c.line()
end
eq("insert: u undoes word by word", steps, { "one two three", "one two ", "one ", "" })
c.keys("<C-r><C-y>U")
eq("redo: Ctrl+R, Ctrl+Y and U", c.line(), "one two three")
c.keys("<C-z>")
eq("undo: Ctrl+Z", c.line(), "one two ")
c.stop()

c = child()
c.keys("ione two<Esc>$.")
eq("dot: repeats the whole insert", c.line(), "one twone twoo")
c.lua([[vim.fn.setreg("q", "Aa b c\27")]])
c.keys("o<Esc>@q")
eq("macro: replays intact", c.line(), "a b c")
c.keys("u")
eq("macro: its insert is one undo step", c.lines(), { "one twone twoo", "" })
c.stop()

c = child()
c.lua([[vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha beta gamma" })]])
c.keys("yiwwx")
eq("x: deletes", c.line(), "alpha eta gamma")
eq("x: the clipboard keeps the yank", c.lua([[return vim.fn.getreg('"')]]), "alpha")
c.keys("ciwBETA<Esc>")
eq("c: the clipboard keeps the yank", c.lua([[return vim.fn.getreg('"')]]), "alpha")
c.keys("wviwp")
eq("visual p: replaces", c.line(), "alpha BETA alpha")
eq("visual p: the clipboard keeps the yank", c.lua([[return vim.fn.getreg('"')]]), "alpha")
c.keys('"ax')
eq("explicit register: x copies into it", c.lua([[return vim.fn.getreg("a")]]), "a")
c.stop()

c = child()
c.lua([[require("history.yanks").clear() vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })]])
c.keys("yyjyyjyyGo<Esc>p")
eq("paste: the last yank", c.lines()[5], "three")
c.keys("[y")
eq("[y: swaps for the older one", c.lines()[5], "two")
c.keys("[y")
eq("[y: again", c.lines()[5], "one")
c.keys("]y")
eq("]y: back to the newer one", c.lines()[5], "two")
eq("[y: one line pasted, never more", #c.lines(), 5)
c.keys("u")
eq("u: the swapped paste is one step", #c.lines(), 4)
eq("registers untouched", c.lua([[return { vim.fn.getreg('"'), vim.fn.getreg("z") }]]), { "three\n", "" })
eq(
	"history: newest first",
	c.lua([[return vim.tbl_map(function(e) return e.lines[1] end, require("history.yanks").list())]]),
	{ "three", "two", "one" }
)
c.lua([[require("history.yanks").save()]])
c.stop()

c = child()
eq(
	"persist: the list survives a restart",
	c.lua([[return vim.tbl_map(function(e) return e.lines[1] end, require("history.yanks").list())]]),
	{ "three", "two", "one" }
)
c.stop()
vim.fn.delete(initfile)

print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
	print("ALL OK")
else
	print("FAILURES")
end
vim.cmd("qa!")
