-- Tests of the Python REPL workspace (nvim/lua/pyrepl): pure cell/output helpers, the session folder and the menu's
-- new group. Hermetic: a throwaway XDG_STATE_HOME and nvim -u NONE.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-pyrepl.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

package.loaded["core.settings"] = {
  python = { repl = { output_lines = 120 } },
  fim = { enabled = false },
}

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

local cells = require "pyrepl.cells"
local out = require "pyrepl.output"
local model = require "pyrepl.model"
local files = require "pyrepl.files"

-- cells -----------------------------------------------------------------------
ok("marker", cells.is_marker("# %%") and cells.is_marker("  #%%") and not cells.is_marker("# just a comment"))
local lines = {
  "import math",
  "",
  "def add(a, b):",
  "    return a + b",
  "",
  "# %%",
  "x = add(1, 2)",
  "print(x)",
}
eq("parse cells", cells.parse(lines), {
  { first = 1, last = 5 },
  { marker = 6, first = 7, last = 8 },
})
eq("cell at cursor", cells.at(lines, 4).first, 1)
eq("cell at marker", cells.at(lines, 6).marker, 6)
eq("cell text", cells.text(lines, cells.at(lines, 6)), "x = add(1, 2)\nprint(x)")

local split = cells.split { "import math", "x = 1", "", "def f():", "    return x", "", "class A:", "    pass" }
eq("split into cells", split, {
  "import math",
  "",
  "# %%",
  "x = 1",
  "",
  "# %%",
  "def f():",
  "    return x",
  "",
  "# %%",
  "class A:",
  "    pass",
})
eq("split is idempotent", cells.split(split), split)
eq("split leaves marked files alone", cells.split { "# %%", "x = 1" }, { "# %%", "x = 1" })

-- output ----------------------------------------------------------------------
eq("strip ansi", out.strip("\27[31mred\27[0m"), "red")
local blocks = out.parse(table.concat({
  "In [1]: 1 + 2",
  "Out[1]: 3",
  "In [2]: [1, 23, 3]",
  "Out[2]: [1, 23, 3]",
}, "\n"))
eq("ipython blocks", #blocks, 2)
eq("first prompt", blocks[1].label, "In [1]:")
eq("first code", blocks[1].lines[1], "1 + 2")
eq("first output", blocks[1].lines[2], "Out[1]: 3")
local plain = out.parse(">>> 2 * 3\n6\n>>> x = 1")
eq("python prompts", plain[1].label, ">>>")
eq("python blocks", #plain, 2)
ok("render has separators", out.text(blocks):find("── In [1]:", 1, true) ~= nil)

-- model -----------------------------------------------------------------------
eq("clean fenced code", model.clean_code("Here you go:\n```python\nprint(1)\n```\nDone."), "print(1)")
eq("clean plain code", model.clean_code("  x = 1\n"), "x = 1")

-- session folder --------------------------------------------------------------
local dir = files.dir()
ok("folder exists", vim.fn.isdirectory(dir) == 1)
local path = files.ensure("demo", "/tmp/project")
eq("session file", path, dir .. "/demo.py")
ok("cell file created", vim.fn.filereadable(path) == 1)
ok("sessions.json created", vim.fn.filereadable(files.state_path()) == 1)
ok("session listed", vim.list_contains(files.names(), "demo"))
eq("last session", files.last(), "demo")
ok("safe names", files.safe("a/b c") == "a_b_c")
files.save_output("demo", "example output")
ok("output file", vim.fn.filereadable(files.output_file("demo")) == 1)

-- menu wiring -----------------------------------------------------------------
local python = require "languages.python"
eq("REPL group", python.menu.groups.C, "REPL / IPython")
local maps = python.menu.maps
local keys = {}
for _, m in ipairs(maps) do
  keys[m[1]] = true
end
for _, key in ipairs { "Cn", "Cc", "Cx", "Co", "Ca", "Cg", "Ct", "Cf" } do
  ok("map " .. key, keys[key] == true)
end

if fails == 0 then
  print("ALL OK (" .. total .. " checks)")
else
  print("FAILURES: " .. fails .. "/" .. total)
end
vim.cmd(fails == 0 and "qa!" or "cquit 1")
