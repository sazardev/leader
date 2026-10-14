-- Tests of copying diagnostics (nvim/lua/utils/diagcopy.lua): the text, and what each scope collects.
--   nvim -u NONE --headless -c "luafile scripts/test-diagcopy.lua"
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

local notes = {}
package.loaded["utils.log"] = {
  info = function(m)
    notes[#notes + 1] = m
  end,
}
local dc = require "utils.diagcopy"

-- ── the text ────────────────────────────────────────────────────────────────
eq(
  "format: compiler style with source and code",
  dc.format {
    {
      path = "a.go",
      lnum = 9,
      col = 11,
      severity = 1,
      source = "gopls",
      code = "UndeclaredName",
      message = "undefined: context",
    },
  },
  "a.go:10:12: error: undefined: context (gopls UndeclaredName)"
)
eq(
  "format: severities by name",
  dc.format {
    { path = "a", lnum = 0, col = 0, severity = 2, message = "w" },
    { path = "b", lnum = 0, col = 0, severity = 3, message = "i" },
    { path = "c", lnum = 0, col = 0, severity = 4, message = "h" },
  },
  "a:1:1: warning: w\nb:1:1: info: i\nc:1:1: hint: h"
)
eq(
  "format: no source or code, no parentheses",
  dc.format { { path = "a", lnum = 0, col = 0, severity = 1, message = "boom" } },
  "a:1:1: error: boom"
)
eq(
  "format: a source alone",
  dc.format { { path = "a", lnum = 0, col = 0, severity = 1, source = "ruff", message = "x" } },
  "a:1:1: error: x (ruff)"
)
eq(
  "format: a multi-line message keeps its lines, indented",
  dc.format { { path = "a", lnum = 0, col = 0, severity = 1, message = "first\nsecond\n   third" } },
  "a:1:1: error: first\n  second\n  third"
)
eq(
  "format: ordered by file, line and column",
  dc.format {
    { path = "b", lnum = 0, col = 0, message = "3" },
    { path = "a", lnum = 5, col = 0, message = "2" },
    { path = "a", lnum = 1, col = 9, message = "1b" },
    { path = "a", lnum = 1, col = 2, message = "1a" },
  },
  "a:2:3: error: 1a\na:2:10: error: 1b\na:6:1: error: 2\nb:1:1: error: 3"
)
eq("format: nothing", dc.format {}, "")

-- ── what each scope collects ────────────────────────────────────────────────
local ns = vim.api.nvim_create_namespace "t"
local function buffer(name, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/" .. name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end
local one = buffer("one.go", { "a", "b", "c" })
local two = buffer("two.go", { "x", "y" })
vim.api.nvim_set_current_buf(one)
vim.diagnostic.set(ns, one, {
  { lnum = 0, col = 0, severity = 1, message = "first", source = "gopls" },
  { lnum = 1, col = 2, severity = 2, message = "second" },
  { lnum = 1, col = 0, severity = 3, message = "same line" },
})
vim.diagnostic.set(ns, two, { { lnum = 1, col = 0, severity = 1, message = "elsewhere" } })

vim.api.nvim_win_set_cursor(0, { 2, 0 })
eq(
  "line: only the cursor line's",
  vim.tbl_map(function(d)
    return d.message
  end, dc.collect "line"),
  { "second", "same line" }
)
eq("file: the whole buffer", #dc.collect "file", 3)
eq(
  "all: every open buffer, with relative paths",
  vim.tbl_map(function(d)
    return d.path
  end, dc.collect "all"),
  { "one.go", "one.go", "one.go", "two.go" }
)

-- ── copying ─────────────────────────────────────────────────────────────────
vim.opt.clipboard = ""
dc.copy "line"
eq("copy: the register holds the text", vim.fn.getreg "+" ~= "" or vim.fn.getreg '"' ~= "", true)
eq("copy: the unnamed register has it", vim.fn.getreg '"', "one.go:2:1: info: same line\none.go:2:3: warning: second")
eq("copy: says how many", notes[#notes], "Copied 2 diagnostics on this line")
dc.copy "all"
eq("copy: everything", notes[#notes], "Copied 4 diagnostics in the project")
vim.diagnostic.reset(ns)
dc.copy "file"
eq(
  "copy: nothing to copy says so and keeps the register",
  { notes[#notes], vim.fn.getreg('"'):match "^one.go:1:1" ~= nil },
  { "No diagnostics in this file", true }
)

print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
