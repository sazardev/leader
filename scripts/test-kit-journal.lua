-- Taking a build back (nvim/lua/agent/kit/build/journal.lua): created files go, replaced ones return from the trash, what
-- you changed since is left alone, only the last build is kept. Hermetic: temp project, temp state dir, no network.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-journal.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end

local journal = require "agent.kit.build.journal"
local ops = require "files.ops"

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/src", "p")

--- What the build's write_file does around a file
local function write(started, path, content)
  local full = dir .. "/" .. path
  local entry
  if vim.uv.fs_stat(full) then
    entry = ops.trash(full)
  end
  vim.fn.mkdir(vim.fs.dirname(full), "p")
  local f = io.open(full, "w")
  f:write(content)
  f:close()
  journal.record(dir, started, path, content, entry)
end
local function read(path)
  local f = io.open(dir .. "/" .. path, "r")
  if not f then
    return nil
  end
  local t = f:read "*a"
  f:close()
  return t
end

-- a project with a file the build will replace
vim.fn.writefile({ "old main" }, dir .. "/main.go")

eq("nothing to undo before a build", journal.last(dir), nil)
eq("undo with no journal", journal.undo(dir), nil)

write(100, "main.go", "new main\n")
write(100, "src/a.go", "package src\n")
write(100, "src/deep/b.go", "package deep\n")
eq("the journal counts replaced and created", journal.last(dir), { files = 3, created = 2, replaced = 1 })

-- a fix round rewrites a file: the FIRST original is still the one that comes back
write(100, "main.go", "fixed main\n")
eq("a rewrite keeps one entry", journal.last(dir), { files = 3, created = 2, replaced = 1 })

local r = journal.undo(dir)
eq("everything comes back", { r.restored, r.removed, #r.skipped }, { 1, 2, 0 })
eq("the replaced file is the ORIGINAL", read "main.go", "old main\n")
eq("created files are gone", { read "src/a.go", read "src/deep/b.go" }, { nil, nil })
eq(
  "folders the build made are gone",
  { vim.uv.fs_stat(dir .. "/src") ~= nil, vim.uv.fs_stat(dir .. "/src/deep") ~= nil },
  { false, false }
)
eq("the journal is spent", journal.last(dir), nil)

-- a file the user edited after the build is never touched
write(200, "main.go", "build two\n")
write(200, "extra.go", "package extra\n")
local f = io.open(dir .. "/extra.go", "a")
f:write "// my own change\n"
f:close()
r = journal.undo(dir)
eq("the edited file is skipped", { r.restored, r.removed, #r.skipped }, { 1, 0, 1 })
eq("and says why", r.skipped[1], { path = "extra.go", why = "edited since" })
eq("its content is untouched", read "extra.go", "package extra\n// my own change\n")
eq("the other file was restored", read "main.go", "old main\n")
eq("what could not be undone stays in the journal", journal.last(dir), { files = 1, created = 1, replaced = 0 })

-- a file deleted by hand is skipped, not an error
vim.fn.delete(dir .. "/extra.go")
r = journal.undo(dir)
eq("a file that is already gone is reported", r.skipped[1], { path = "extra.go", why = "gone" })
vim.fn.delete(journal.path(dir))

-- only the last build is kept
write(300, "one.go", "1\n")
write(400, "two.go", "2\n")
eq("a new run replaces the journal", journal.last(dir), { files = 1, created = 1, replaced = 0 })
r = journal.undo(dir)
eq("only the last build is undone", { read "one.go", read "two.go" }, { "1\n", nil })

-- the original left the trash: say so, never delete the build's file for nothing
vim.fn.writefile({ "orig" }, dir .. "/keep.go")
write(500, "keep.go", "built\n")
local entry = journal.load(dir).files[1]
vim.fn.delete(entry.stored, "rf")
r = journal.undo(dir)
eq(
  "a lost original is reported and the file stays",
  { r.skipped[1].why, read "keep.go" },
  { "the original left the trash", "built\n" }
)

print(fails == 0 and ("\nALL OK (" .. total .. " checks)") or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
