-- Tests of the GitHub menu (nvim/lua/github, <leader>Gh): the catalog/parsers (pure), the launcher and setup flow
-- with a fake `gh` (no network), and the guards. octo.nvim is only checked, never loaded.
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

local catalog = require "github.catalog"

-- ── catalog and parsers (pure) ───────────────────────────────────────────────

local LIST = "REPO\tCOMMAND\tVERSION\ndlvhdr/gh-dash\tgh-dash\tv4.26.2\n"
local set = catalog.installed(LIST)
eq("installed: repo and command, header skipped", { set["dlvhdr/gh-dash"], set["gh-dash"], set.REPO }, { true, true, nil })
eq("installed: no extensions", catalog.installed "", {})
eq("get: known and unknown ids", { catalog.get("dash").label, catalog.get("nope") }, { "gh-dash", nil })
local dash = catalog.get "dash"
local observer = catalog.get "observer"
eq("is_installed: by repo", catalog.is_installed(dash, set), true)
eq("is_installed: by command name", catalog.is_installed(observer, { ["gh-observer"] = true }), true)
eq("is_installed: missing", catalog.is_installed(observer, set), false)
eq(
  "launch: installed is the plain command",
  catalog.launch(dash, true),
  "gh dash"
)
eq(
  "launch: missing installs first",
  catalog.launch(observer, false),
  "gh extension install fini-net/gh-observer && gh observer"
)
eq("install_lines: one command each, in order", catalog.install_lines { observer, dash }, {
  "gh extension install fini-net/gh-observer",
  "gh extension install dlvhdr/gh-dash",
})
local items, missing = catalog.items(set)
eq(
  "items: missing first, checked, then the installed one",
  { #items, missing, items[1].label, items[1].checked, items[1].group, items[#items].label, items[#items].checked },
  { 4, 3, "gh-observer", true, "missing", "gh-dash", false }
)

-- ── a fake gh in PATH ────────────────────────────────────────────────────────

local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/bin", "p")
local fake = base .. "/bin/gh"
vim.fn.writefile({
  "#!/bin/sh",
  'case "$1 $2" in',
  '  "auth status") exit "${FAKE_GH_AUTH:-0}" ;;',
  '  "extension list") cat "${GH_LIST:-/dev/null}" ;;',
  "esac",
  "exit 0",
}, fake)
vim.fn.setfperm(fake, "rwxr-xr-x")
vim.env.PATH = base .. "/bin:" .. vim.env.PATH
local list = base .. "/extensions.txt"
vim.fn.writefile(vim.split(LIST, "\n", { plain = true }), list)
vim.env.GH_LIST = list

local tui_calls, run_calls, confirms, checklists, notes = {}, {}, {}, {}, {}
package.loaded["utils.terminal"] = {
  run = function(cmd, dir)
    run_calls[#run_calls + 1] = { cmd, dir }
  end,
  tui = function(name, cmd, dir)
    tui_calls[#tui_calls + 1] = { name, cmd, dir }
  end,
}
package.loaded["utils.modal"] = {
  hl = { key = "key", muted = "muted", file = "file", warn = "warn" },
  confirm = function(lines, opts, on_yes)
    confirms[#confirms + 1] = { lines = lines, opts = opts }
    on_yes()
  end,
  checklist = function(items, opts, on_submit)
    checklists[#checklists + 1] = { items = items, opts = opts, submit = on_submit }
  end,
}
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

local github = require "github"

-- ── launching ────────────────────────────────────────────────────────────────

eq("installed: read from the fake gh", github.installed()["gh-dash"], true)
github.launch "dash"
eq("launch: an installed TUI opens in its own terminal", tui_calls[1], { "gh-dash", "gh dash", vim.fn.getcwd() })

github.launch "observer"
eq("launch: a missing one asks first", confirms[1] and confirms[1].opts.title, "gh-observer")
eq(
  "launch: installing and launching in one command",
  tui_calls[2],
  { "gh-observer", "gh extension install fini-net/gh-observer && gh observer", vim.fn.getcwd() }
)

vim.env.FAKE_GH_AUTH = "1"
local before = #tui_calls
github.launch "dash"
eq("launch: not logged in warns and does nothing", { #tui_calls, notes[#notes] }, {
  before,
  "warn: GitHub: not logged in (run `gh auth login`, or <leader>GhA)",
})
vim.env.FAKE_GH_AUTH = ""

-- ── setup ────────────────────────────────────────────────────────────────────

github.setup()
eq("setup: one checklist with the missing ones first", checklists[1].items[1].label, "gh-observer")
eq("setup: installed ones are not checked", checklists[1].items[4].checked, false)
checklists[1].submit { 1, 2, 3 }
eq("setup: Enter installs the checked extensions in one command", run_calls[#run_calls], {
  "gh extension install fini-net/gh-observer && gh extension install dlvhdr/gh-enhance && gh extension install chmouel/gh-news",
  vim.fn.getcwd(),
})

vim.fn.writefile({
  "REPO\tCOMMAND\tVERSION",
  "dlvhdr/gh-dash\tgh-dash\tv4",
  "fini-net/gh-observer\tgh-observer\tv1",
  "dlvhdr/gh-enhance\tgh-enhance\tv1",
  "chmouel/gh-news\tgh-news\tv1",
}, list)
github.setup()
eq("setup: everything installed says so", notes[#notes], "info: GitHub: every extension in the menu is installed")

-- ── core commands and guards ─────────────────────────────────────────────────

github.run "gh auth status"
eq("run: the command goes to the shared terminal", run_calls[#run_calls], { "gh auth status", vim.fn.getcwd() })

local repo = base .. "/repo"
vim.fn.mkdir(repo .. "/.git", "p")
vim.fn.writefile({ "x" }, repo .. "/main.go")
vim.cmd.edit(repo .. "/main.go")
github.run_in_repo "gh browse"
eq("run_in_repo: from the repository root", run_calls[#run_calls], { "gh browse", repo })
vim.cmd "bwipeout!"
local cwd = vim.fn.getcwd()
vim.cmd.cd(base)
before = #run_calls
github.run_in_repo "gh browse"
eq("run_in_repo: outside a repository warns", { #run_calls, notes[#notes] }, {
  before,
  "warn: GitHub: this one needs a repository",
})
vim.cmd.cd(cwd)

github.octo "pr list"
eq("octo: missing plugin says how to get it", notes[#notes], "warn: GitHub: octo.nvim is not installed yet (restart, or run `:Lazy sync`)")

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd(fails == 0 and "qa!" or "cquit 1")
