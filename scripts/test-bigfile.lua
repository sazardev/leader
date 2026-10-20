-- Tests of the big-file guard (nvim/lua/core/bigfile.lua) and of when a save may block on the formatter
-- (nvim/lua/core/saveformat.lua): the pure decisions, then real files opened in this nvim.
--   nvim -u NONE --headless -c "luafile scripts/test-bigfile.lua"
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

local bigfile = require("core.bigfile")
local cfg = { max_bytes = 1000, minified_bytes = 100, minified_line = 50 }

-- ── pure decision ───────────────────────────────────────────────────────────
eq("under the limit", bigfile.is_big(999, 100, cfg), false)
eq("over the limit", bigfile.is_big(1001, 100, cfg), true)
eq("exactly the limit is not big", bigfile.is_big(1000, 100, cfg), false)
eq("empty file", bigfile.is_big(0, 0, cfg), false)
eq("unknown size", bigfile.is_big(nil, nil, cfg), false)
eq("bytes alone decide when lines are unknown", bigfile.is_big(1001, nil, cfg), true)
eq("minified: small but one long line", bigfile.is_big(500, 2, cfg), true)
eq("minified: long lines but under the minified size", bigfile.is_big(90, 1, cfg), false)
eq("normal file of the same size", bigfile.is_big(500, 50, cfg), false)
eq("human: kb", bigfile.human(2048), "2 KB")
eq("human: mb", bigfile.human(3 * 1024 * 1024), "3.0 MB")

-- ── formatting on save: when it may block (lua/core/saveformat.lua) ──────────
local saveformat = require("core.saveformat")
local fcfg = { enabled = true, async_over_lines = 3000 }
eq("save format: a normal file is formatted before the write", saveformat.mode(200, fcfg), "sync")
eq("save format: exactly the limit is still before the write", saveformat.mode(3000, fcfg), "sync")
eq("save format: a bigger one is formatted afterwards, in the background", saveformat.mode(3001, fcfg), "async")
eq("save format: off means never (small)", saveformat.mode(10, { enabled = false, async_over_lines = 3000 }), nil)
eq("save format: off means never (big)", saveformat.mode(90000, { enabled = false, async_over_lines = 3000 }), nil)

-- ── real files ──────────────────────────────────────────────────────────────
local settings = require("core.settings")
settings.bigfile.max_bytes = 200000
bigfile.setup()
vim.cmd("filetype plugin indent on")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function write(name, text)
	local path = dir .. "/" .. name
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	return path
end
local code = string.rep("local function f(a, b)\n  return a + b\nend\n", 10)
local small = write("small.lua", code)
local big = write("big.lua", string.rep(code, 2000)) -- ~ 470 KB
local minified = write("bundle.js", string.rep("var a=1;", 30000)) -- 240 KB, one line, over the byte limit too
local min_small = write("min.js", string.rep("var a=1;", 14000)) -- 112 KB, one line: minified by the line rule

local function open(path)
	vim.cmd("silent edit " .. vim.fn.fnameescape(path))
	return vim.api.nvim_get_current_buf()
end

local b = open(small)
eq("small file keeps its filetype", vim.bo[b].filetype, "lua")
eq("small file is not marked", vim.b[b].bigfile, nil)

b = open(big)
eq("big file becomes bigfile", vim.bo[b].filetype, "bigfile")
eq("big file is marked", vim.b[b].bigfile, true)
eq("big file: no tree-sitter highlighter", vim.treesitter.highlighter.active[b], nil)
eq("big file: no swapfile", vim.bo[b].swapfile, false)
eq("big file: completion off", vim.b[b].completion, false)
eq("big file: folds off", vim.wo.foldenable, false)
eq("big file remembers its size", type(vim.b[b].bigfile_size), "number")

b = open(minified)
eq("a big minified bundle is bigfile", vim.bo[b].filetype, "bigfile")

b = open(min_small)
eq("a small minified bundle is bigfile (one line)", vim.bo[b].filetype, "bigfile")

b = open(small)
eq("going back to the small file: still lua", vim.bo[b].filetype, "lua")


vim.fn.delete(dir, "rf")
if fails > 0 then
	print(("FAILURES: %d of %d"):format(fails, total))
else
	print(("ALL OK (%d checks)"):format(total))
end
vim.cmd("qa!")
