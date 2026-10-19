-- Tests of the release kit (nvim/lua/release, <leader>GR): Conventional Commits → groups and the next version (semver),
-- the CHANGELOG.md section (at the top, never twice), the version read from the project, the checklist (gates from
-- STACK.md, nothing that leaves the machine runs, shipping rows), the PR request, and the flows on a temp git repository
-- with tags. Hermetic: no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-release.lua"
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
local confirms = {}
package.loaded["utils.modal"] = {
  hl = setmetatable({}, {
    __index = function(_, k)
      return k
    end,
  }),
  confirm = function(lines, opts, yes)
    confirms[#confirms + 1] = { title = opts.title, lines = lines }
    yes()
  end,
}

local changelog = require "release.changelog"
local checklist = require "release.checklist"
local release = require "release"

-- ── commits, version, changelog ──────────────────────────────────────────────

local log = table.concat({
  "a1\31feat(notes): export as Markdown\31\30",
  "b2\31fix: empty title crash\31\30",
  "c3\31refactor(api)!: rename the routes\31\30",
  "d4\31chore(release): v1.4.0\31\30",
  "e5\31Merge branch 'x'\31\30",
  "f6\31update readme\31\30",
  "g7\31perf: faster search\31BREAKING CHANGE: the index format changed\30",
}, "\n")
local commits = changelog.parse(log)
eq(
  "parse: types, scopes, breaking (! or BREAKING CHANGE); release commits and merges out",
  vim.tbl_map(function(c)
    return { c.hash, c.type, c.scope or "", c.breaking }
  end, commits),
  {
    { "a1", "feat", "notes", false },
    { "b2", "fix", "", false },
    { "c3", "refactor", "api", true },
    { "f6", "other", "", false },
    { "g7", "perf", "", true },
  }
)
eq("bump: breaking after 1.0 = major", { changelog.bump("1.4.2", commits) }, { "2.0.0", "major" })
eq("bump: breaking before 1.0 = minor", changelog.bump("0.3.1", commits), "0.4.0")
eq("bump: a feature = minor", changelog.bump("1.4.2", { commits[1] }), "1.5.0")
eq("bump: fixes only = patch", changelog.bump("v1.4.2", { commits[2] }), "1.4.3")
eq("bump: nothing to release", changelog.bump("1.4.2", {}), nil)
eq("bump: no version yet = 0.1.0", changelog.bump(nil, { commits[2] }), "0.1.0")
local section = changelog.section("2.0.0", "2026-10-19", commits)
ok("section: the version and date", section:find "^## %[2%.0%.0%] %- 2026%-10%-19\n")
ok(
  "section: breaking changes first, each commit once",
  section:find(
    "### Breaking changes\n\n- **api:** rename the routes (c3)\n- faster search (g7)\n\n### Features",
    1,
    true
  )
)
ok(
  "section: features, fixes, the rest with their type",
  section:find("### Features\n\n- **notes:** export as Markdown (a1)", 1, true)
    and section:find("### Fixes\n\n- empty title crash (b2)", 1, true)
    and section:find("### Other changes\n\n- update readme (f6)", 1, true)
)
ok("section: a perf that is breaking is not listed twice", select(2, section:gsub("faster search", "")) == 1)
local fresh = changelog.insert(nil, "2.0.0", section)
ok(
  "insert: a new file has the header then the section",
  fresh:find "^# Changelog\n\nAll notable changes, newest first."
    and fresh:find("\n\n## [2.0.0] - 2026-10-19\n", 1, true)
)
local older = changelog.insert(fresh:gsub("2%.0%.0", "1.9.0"), "2.0.0", section)
ok("insert: the new version above the older one", older:find("## [2.0.0]", 1, true) < older:find("## [1.9.0]", 1, true))
local again = changelog.insert(older, "2.0.0", changelog.section("2.0.0", "2026-10-20", { commits[2] }))
eq("insert: the same version again replaces its section", select(2, again:gsub("## %[2%.0%.0%]", "")), 1)
local new_part = again:match "## %[2%.0%.0%](.-)## %[1%.9%.0%]" or ""
ok(
  "insert: and keeps the others",
  again:find("## [1.9.0]", 1, true)
    and new_part:find("2026-10-20", 1, true)
    and not new_part:find("rename the routes", 1, true)
)
eq(
  "current: VERSION first",
  { changelog.current { VERSION = "1.2.3\n", ["package.json"] = '{"version":"9.9.9"}' } },
  { "1.2.3", "VERSION" }
)
eq(
  "current: package.json",
  { changelog.current { ["package.json"] = '{ "name": "x", "version": "0.4.1" }' } },
  { "0.4.1", "package.json" }
)
eq(
  "current: pubspec with a build number",
  { changelog.current { ["pubspec.yaml"] = "name: app\nversion: 1.0.2+7\n" } },
  { "1.0.2+7", "pubspec.yaml" }
)
eq(
  "current: Cargo's package",
  { changelog.current { ["Cargo.toml"] = '[package]\nname = "x"\nversion = "0.2.0"\n' } },
  { "0.2.0", "Cargo.toml" }
)
eq("current: none", { changelog.current {} }, {})

-- ── checklist ────────────────────────────────────────────────────────────────

local stack = table.concat({
  "# STACK",
  "",
  "## Stack",
  "",
  "| Area | Choice |",
  "|---|---|",
  "| Language | Dart |",
  "| Deploy | Stores with fastlane |",
  "| CI | GitHub Actions |",
  "",
  "## Commands",
  "",
  "- Run tests: `flutter test`",
  "",
  "## Quality gates",
  "",
  "- `dart format --set-exit-if-changed .`",
  "- `flutter analyze`",
  "- `fastlane deploy beta`",
  "- `flutter`",
  "",
  "## Rules for agents",
}, "\n")
eq(
  "gates: the Quality gates commands (a lone tool name is not one)",
  checklist.gates(stack),
  { "dart format --set-exit-if-changed .", "flutter analyze", "fastlane deploy beta" }
)
eq(
  "gates: from Commands when there are none",
  checklist.gates((stack:gsub("## Quality gates.-## Rules", "## Rules"))),
  { "flutter test" }
)
eq(
  "runnable: local checks yes, what leaves the machine no",
  {
    checklist.runnable "flutter analyze",
    checklist.runnable "fastlane deploy beta",
    checklist.runnable "git push --tags",
  },
  { true, false, false }
)
eq("shipping: deploy and CI rows", checklist.shipping(stack), { "Deploy: Stores with fastlane", "CI: GitHub Actions" })
local lines, actions = checklist.render {
  clean = false,
  branch = "main",
  ahead = 2,
  behind = 0,
  version = "1.4.2",
  version_file = "pubspec.yaml",
  next = "1.5.0",
  tag = "v1.4.2",
  commits = 3,
  changelog = false,
  ci = { ".github/workflows/ci.yml" },
  stack = stack,
}
local text = table.concat(lines, "\n")
ok("render: the next version in the title", lines[1] == "# Release · v1.5.0")
ok("render: a dirty tree is unchecked", text:find("- [ ] uncommitted changes", 1, true))
ok(
  "render: the gates, the deploy one by hand",
  text:find("- [ ] `flutter analyze` · ⏎ runs it", 1, true) and text:find("`fastlane deploy beta` (by hand", 1, true)
)
ok(
  "render: changelog and version items",
  text:find("- [ ] CHANGELOG.md has v1.5.0 · ⏎ writes it", 1, true)
    and text:find("- [ ] pubspec.yaml says 1.4.2 (next: 1.5.0)", 1, true)
)
ok("render: CI found", text:find("- [x] CI: .github/workflows/ci.yml", 1, true))
local kinds = {}
for _, a in pairs(actions) do
  kinds[a.kind] = (kinds[a.kind] or 0) + 1
end
eq(
  "render: ⏎ runs two gates, writes the changelog, opens the version file",
  kinds,
  { run = 2, changelog = 1, open = 1 }
)

-- ── PR request ───────────────────────────────────────────────────────────────

local req = release.pr_request("feat/export", "origin/main", { "feat(notes): export" }, " a | 2 +-", "diff --git a b")
eq("pr: light tier, its own action", { req.action, req.tier }, { "release_pr", "light" })
ok(
  "pr: the four sections asked",
  req.system:find("## Summary", 1, true)
    and req.system:find("## Changes", 1, true)
    and req.system:find("## How to test", 1, true)
    and req.system:find("## Risks", 1, true)
)
ok(
  "pr: branch, commits, stat and diff sent",
  req.prompt:find("<branch>feat/export → origin/main</branch>", 1, true)
    and req.prompt:find("feat(notes): export", 1, true)
    and req.prompt:find("diff --git a b", 1, true)
)

-- ── on a real repository ─────────────────────────────────────────────────────

local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local function git(...)
  return vim
    .system(
      vim.list_extend({ "git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false" }, { ... }),
      { cwd = repo, text = true }
    )
    :wait()
end
git("init", "-q", "-b", "main")
local function commit(msg)
  local f = assert(io.open(repo .. "/f.txt", "a"))
  f:write(msg .. "\n")
  f:close()
  git("add", ".")
  git("commit", "-q", "-m", msg)
end
commit "feat: first"
git("tag", "v0.1.0")
commit "feat(notes): export"
commit "fix: crash"
local tag, since = release.since(repo)
eq("since: the last tag and the commits after it", { tag, #since, since[1].subject }, { "v0.1.0", 2, "crash" })
eq("base: main when there is no origin", release.base(repo), "main")
vim.cmd.edit(vim.fn.fnameescape(repo .. "/f.txt"))
release.changelog()
eq("changelog flow: asked first, with the file name", confirms[#confirms].title, "CHANGELOG.md")
local written = table.concat(vim.fn.readfile(repo .. "/CHANGELOG.md"), "\n")
ok(
  "changelog flow: v0.2.0 written with both commits",
  written:find("## [0.2.0]", 1, true)
    and written:find("- **notes:** export", 1, true)
    and written:find("- crash", 1, true)
)
ok("changelog flow: says what to do next", notes[#notes]:find("git tag v0.2.0", 1, true))
git("tag", "v0.2.0")
local before = #notes
release.changelog()
ok(
  "changelog flow: nothing since the tag",
  #notes == before + 1 and notes[#notes]:find("no commits since v0.2.0", 1, true)
)

vim.fn.delete(repo, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
