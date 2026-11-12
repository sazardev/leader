-- Tests of the GoHawk diagnostics (nvim/lua/utils/gohawk.lua): the JSON parser, the per-buffer filter, the severity of
-- defects vs hazards, the related evidence, the quickfix list and the module root. Pure apart from temp files.
-- Run by scripts/test-go.sh.
local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print(("FAIL %s\n  got:  %s\n  want: %s"):format(name, vim.inspect(got), vim.inspect(want)))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end
local function group(title)
  print("\n── " .. title .. " ──")
end

local gohawk = require "utils.gohawk"

local sample = [[
{
  "example.com/hawk": {
    "deferinloop": [
      {
        "category": "deferinloop/cleanup-lifetime",
        "posn": "/tmp/gohawk-test/main.go:26:3",
        "end": "/tmp/gohawk-test/main.go:26:18",
        "message": "deferred cleanup runs after the loop instead of after this iteration",
        "related": [
          {
            "posn": "/tmp/gohawk-test/main.go:21:2",
            "end": "/tmp/gohawk-test/main.go:21:5",
            "message": "each iteration of this loop defers another cleanup"
          }
        ]
      }
    ],
    "resourcelifetime": [
      {
        "category": "resourcelifetime/missing-release",
        "posn": "/tmp/gohawk-test/other.go:10:2",
        "end": "/tmp/gohawk-test/other.go:10:10",
        "message": "file is not closed on this return path",
        "related": []
      }
    ]
  }
}
]]

-- ── parser ───────────────────────────────────────────────────────────────────
group("parse")
local findings = gohawk.parse(sample)
eq("parse: one finding per diagnostic", #findings, 2)
eq("parse: sorted by file/line", findings[1].category, "deferinloop/cleanup-lifetime")
eq("parse: position", { findings[1].line, findings[1].col }, { 26, 3 })
eq("parse: end span", { findings[1].end_line, findings[1].end_col }, { 26, 18 })
eq("parse: package", findings[1].package, "example.com/hawk")
eq("parse: analyzer", findings[1].analyzer, "deferinloop")
eq("parse: hazard is a warning", findings[1].severity, "warn")
eq("parse: defect is an error", findings[2].severity, "error")
ok("parse: detail keeps the evidence", gohawk.detail(findings[1]):find("each iteration", 1, true) ~= nil)
ok("parse: detail points at the evidence line", gohawk.detail(findings[1]):find("line 21", 1, true) ~= nil)
ok("parse: detail keeps the message", gohawk.detail(findings[1]):find("deferred cleanup", 1, true) ~= nil)
eq("parse: empty output", gohawk.parse "", {})
eq("parse: invalid JSON", gohawk.parse "not json", {})

-- ── diagnostics ──────────────────────────────────────────────────────────────
group("diagnostics")
local main_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(main_buf, "/tmp/gohawk-test/main.go")
local main_diags = gohawk.diagnostics(sample, main_buf, "/tmp/gohawk-test")
eq("diagnostics: only the buffer's file", #main_diags, 1)
eq("diagnostics: 0-based line", main_diags[1].lnum, 25)
eq("diagnostics: 0-based column", main_diags[1].col, 2)
eq("diagnostics: end span", { main_diags[1].end_lnum, main_diags[1].end_col }, { 25, 17 })
eq("diagnostics: warning severity", main_diags[1].severity, vim.diagnostic.severity.WARN)
eq("diagnostics: source", main_diags[1].source, "gohawk")
eq("diagnostics: check as code", main_diags[1].code, "deferinloop/cleanup-lifetime")
ok("diagnostics: message carries the related evidence", main_diags[1].message:find("each iteration", 1, true) ~= nil)
vim.api.nvim_buf_delete(main_buf, { force = true })

local other_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(other_buf, "/tmp/gohawk-test/other.go")
local other_diags = gohawk.diagnostics(sample, other_buf, "/tmp/gohawk-test")
eq("diagnostics: the defect is an error", { #other_diags, other_diags[1] and other_diags[1].severity }, { 1, vim.diagnostic.severity.ERROR })
vim.api.nvim_buf_delete(other_buf, { force = true })

-- ── quickfix ─────────────────────────────────────────────────────────────────
group("quickfix")
gohawk.quickfix(findings)
local qf = vim.fn.getqflist()
eq("quickfix: one item per finding", #qf, 2)
eq("quickfix: line", qf[1].lnum, 26)
eq("quickfix: warning type", qf[1].type, "W")
eq("quickfix: error type", qf[2].type, "E")
ok("quickfix: category in the text", qf[1].text:find("deferinloop/cleanup-lifetime", 1, true) ~= nil)
ok("quickfix: related evidence in the text", qf[1].text:find("each iteration", 1, true) ~= nil)
vim.fn.setqflist({}, "r", { title = "gohawk", items = {} })

-- ── module root ──────────────────────────────────────────────────────────────
group("root")
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/internal/pkg", "p")
vim.fn.writefile({ "module example.com/x", "", "go 1.26" }, tmp .. "/go.mod")
vim.fn.writefile({ "package pkg" }, tmp .. "/internal/pkg/x.go")
eq("root: nearest go.mod", gohawk.root(tmp .. "/internal/pkg/x.go"), vim.fs.normalize(tmp))
local bare = vim.fn.tempname()
vim.fn.mkdir(bare, "p")
vim.fn.writefile({ "package main" }, bare .. "/main.go")
eq("root: without a module, the file's folder", gohawk.root(bare .. "/main.go"), vim.fs.normalize(bare))
vim.fn.delete(tmp, "rf")
vim.fn.delete(bare, "rf")

print(("\nALL OK (%d checks)"):format(total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
