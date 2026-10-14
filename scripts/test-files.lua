-- Tests of the file operations (nvim/lua/files): path helpers, the file system side (create, rename, copy, trash and
-- restore), what a move does to open buffers, and the flows behind the modals. Hermetic: a temp project and state dir.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-files.lua"
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

local paths = require "files.paths"
local ops = require "files.ops"

-- ── paths (pure) ────────────────────────────────────────────────────────────
eq(
  "split: several, trimmed, a slash makes a folder",
  paths.split " a.go ;b/c.go; d/ ;; ",
  { { name = "a.go", dir = false }, { name = "b/c.go", dir = false }, { name = "d", dir = true } }
)
eq("split: nothing", paths.split "  ; ", {})
eq("valid: a normal path", { paths.valid "src/ui/menu.go" }, { true })
eq("valid: empty", { paths.valid "" }, { false, "the name is empty" })
eq("valid: dot segments are not names", { paths.valid "a/../b" }, { false, "'.' and '..' are not names" })
eq("resolve: relative to the base", paths.resolve("/p/src", "ui/a.go"), "/p/src/ui/a.go")
eq("resolve: absolute as typed", paths.resolve("/p/src", "/tmp/x.go"), "/tmp/x.go")
eq(
  "inside: the folder and what is under it, not a sibling with the same prefix",
  { paths.inside("/p/a", "/p/a"), paths.inside("/p/a/b.go", "/p/a"), paths.inside("/p/ab/c.go", "/p/a") },
  { true, true, false }
)
eq("rebase: a file inside a moved folder follows", {
  paths.rebase("/p/a/b.go", "/p/a", "/p/z"),
  paths.rebase("/p/a", "/p/a", "/p/z"),
  paths.rebase("/p/ab", "/p/a", "/p/z"),
}, { "/p/z/b.go", "/p/z", nil })
eq(
  "copy_name: before the extension",
  paths.copy_name("/p/note.go", function()
    return false
  end),
  "/p/note_copy.go"
)
eq(
  "copy_name: counts up while the name is taken",
  paths.copy_name("/p/note.go", function(c)
    return c == "/p/note_copy.go" or c == "/p/note_copy2.go"
  end),
  "/p/note_copy3.go"
)
eq("copy_name: no extension, and a dotfile keeps its dot", {
  paths.copy_name("/p/Makefile", function()
    return false
  end),
  paths.copy_name("/p/.env", function()
    return false
  end),
}, { "/p/Makefile_copy", "/p/.env_copy" })
eq(
  "display: relative inside the project, ~ outside",
  { paths.display("/p/src/a.go", "/p"), paths.display("/p", "/p") ~= "" },
  { "src/a.go", true }
)

-- ── the file system ─────────────────────────────────────────────────────────
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
dir = vim.uv.fs_realpath(dir)
vim.cmd("cd " .. vim.fn.fnameescape(dir))
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "x\n")
  f:close()
end
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local s = f:read "*a"
  f:close()
  return s
end

eq("create: a file, and the folders on the way", { ops.create(dir .. "/src/ui/menu.go", false) }, { true })
ok("create: it is there", ops.exists(dir .. "/src/ui/menu.go") and ops.is_dir(dir .. "/src/ui"))
eq("create: never overwrites", { ops.create(dir .. "/src/ui/menu.go", false) }, { nil, "already exists" })
eq("create: a folder", { ops.create(dir .. "/docs/img", true) }, { true })
ok("create: it is a folder", ops.is_dir(dir .. "/docs/img"))
write(dir .. "/plain.txt")
eq(
  "create: below a file fails with a reason",
  { ops.create(dir .. "/plain.txt/inner.go", false) },
  { nil, dir .. "/plain.txt is a file" }
)

write(dir .. "/src/a.go", "package a\n")
eq("rename: moves a file", { ops.rename(dir .. "/src/a.go", dir .. "/src/b.go") }, { true })
ok(
  "rename: the old one is gone and the content came along",
  not ops.exists(dir .. "/src/a.go") and read(dir .. "/src/b.go") == "package a\n"
)
eq(
  "rename: into a folder that does not exist yet",
  { ops.rename(dir .. "/src/b.go", dir .. "/pkg/deep/b.go") },
  { true }
)
write(dir .. "/src/c.go", "c")
eq("rename: never overwrites", { ops.rename(dir .. "/src/c.go", dir .. "/pkg/deep/b.go") }, { nil, "already exists" })
eq(
  "rename: the same path is not a move",
  { ops.rename(dir .. "/src/c.go", dir .. "/src/c.go") },
  { nil, "that is the same path" }
)
eq(
  "rename: a folder cannot go into itself",
  { ops.rename(dir .. "/src", dir .. "/src/ui/src") },
  { nil, "cannot move a folder into itself" }
)
eq("rename: a whole folder", { ops.rename(dir .. "/src/ui", dir .. "/ui") }, { true })
ok("rename: its contents came along", read(dir .. "/ui/menu.go") == "x\n" or ops.exists(dir .. "/ui/menu.go"))

eq("copy: a file", { ops.copy(dir .. "/src/c.go", dir .. "/src/c_copy.go") }, { true })
ok("copy: both exist", ops.exists(dir .. "/src/c.go") and read(dir .. "/src/c_copy.go") == "c")
eq("copy: never overwrites", { ops.copy(dir .. "/src/c.go", dir .. "/src/c_copy.go") }, { nil, "already exists" })
write(dir .. "/tree/a/b.go", "b")
write(dir .. "/tree/z.go", "z")
eq("copy: a folder with what is inside", { ops.copy(dir .. "/tree", dir .. "/tree2") }, { true })
ok("copy: nested files too", read(dir .. "/tree2/a/b.go") == "b" and read(dir .. "/tree2/z.go") == "z")
eq(
  "copy: a folder into itself is refused",
  { ops.copy(dir .. "/tree", dir .. "/tree/inner") },
  { nil, "cannot copy a folder into itself" }
)
eq("count: files and folders inside", { ops.count(dir .. "/tree") }, { 2, 1 })

-- ── trash ───────────────────────────────────────────────────────────────────
eq("restore: nothing in the trash", { ops.restore() }, { nil, "the trash is empty" })
local entry = ops.trash(dir .. "/src/c.go")
ok(
  "trash: the file left its place and is stored",
  entry ~= nil and not ops.exists(dir .. "/src/c.go") and read(entry.stored) == "c"
)
local folder_entry = ops.trash(dir .. "/tree")
ok(
  "trash: a folder goes whole",
  folder_entry ~= nil and not ops.exists(dir .. "/tree") and read(folder_entry.stored .. "/a/b.go") == "b"
)
write(dir .. "/same/note.txt", "1")
local first = ops.trash(dir .. "/same/note.txt")
write(dir .. "/same/note.txt", "2")
local second = ops.trash(dir .. "/same/note.txt")
ok(
  "trash: two things with one name in the same second do not collide",
  first and second and first.stored ~= second.stored
)
eq("restore: the most recent comes back first", { ops.restore() }, { dir .. "/same/note.txt" })
eq("restore: with its content", read(dir .. "/same/note.txt"), "2")
write(dir .. "/same/note.txt", "taken")
eq("restore: refuses to overwrite and says what is in the way", { select(2, ops.restore()) ~= nil }, { true })
os.remove(dir .. "/same/note.txt")
eq("restore: then it comes back", { ops.restore() }, { dir .. "/same/note.txt" })
eq("restore: and then the folder", { ops.restore() }, { dir .. "/tree" })
ok("restore: the folder is whole again", read(dir .. "/tree/a/b.go") == "b")
eq("restore: and then the first file", { ops.restore() }, { dir .. "/src/c.go" })
eq("restore: empty again", { ops.restore() }, { nil, "the trash is empty" })

-- ── folders to pick ─────────────────────────────────────────────────────────
vim.fn.mkdir(dir .. "/node_modules/pkg", "p")
vim.fn.mkdir(dir .. "/.git/objects", "p")
local folders = ops.folders(dir)
ok(
  "folders: shallowest first, with what the project has",
  folders[1] ~= nil and vim.tbl_contains(folders, "pkg/deep") and vim.tbl_contains(folders, "tree")
)
ok(
  "folders: never node_modules or .git",
  not vim.tbl_contains(folders, "node_modules")
    and not vim.tbl_contains(folders, "node_modules/pkg")
    and not vim.tbl_contains(folders, ".git")
)
ok("folders: the folder being moved is left out", not vim.tbl_contains(ops.folders(dir, dir .. "/tree"), "tree/a"))

-- ── buffers follow ──────────────────────────────────────────────────────────
local buffers = require "files.buffers"
write(dir .. "/live/a.go", "package a\n")
vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/live/a.go"))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "package a", "// unsaved" })
ops.rename(dir .. "/live", dir .. "/moved")
eq("buffers: one followed", buffers.renamed(dir .. "/live", dir .. "/moved"), 1)
eq(
  "buffers: it is the same buffer under its new name",
  vim.fs.normalize(vim.api.nvim_buf_get_name(buf)),
  dir .. "/moved/a.go"
)
eq(
  "buffers: and its unsaved work is still there",
  vim.api.nvim_buf_get_lines(buf, 0, -1, false),
  { "package a", "// unsaved" }
)
ok("buffers: no ghost buffer is left under the old name", vim.fn.bufnr("^" .. dir .. "/live/a.go$") == -1)
eq("buffers: unsaved ones are counted before a delete", buffers.unsaved_inside(dir .. "/moved"), 1)
vim.cmd "write"
eq("buffers: saved ones are not", buffers.unsaved_inside(dir .. "/moved"), 0)
ok("buffers: the save went to the new place", read(dir .. "/moved/a.go") == "package a\n// unsaved\n")
vim.cmd "split"
eq("buffers: a deleted file's buffer goes", buffers.removed(dir .. "/moved/a.go"), 1)
ok(
  "buffers: and its windows did not close with it",
  #vim.api.nvim_list_wins() == 2 and not vim.api.nvim_buf_is_valid(buf)
)
vim.cmd "only"

-- ── the flows behind the modals ─────────────────────────────────────────────
local asked = {}
package.loaded["utils.modal"] = {
  hl = setmetatable({}, {
    __index = function()
      return "x"
    end,
  }),
  input = function(lines, opts, cb)
    asked = { kind = "input", lines = lines, opts = opts, cb = cb }
  end,
  confirm = function(lines, opts, cb)
    asked = { kind = "confirm", lines = lines, opts = opts, cb = cb }
  end,
}
package.loaded["files"] = nil
package.loaded["files.location"] = nil
local files = require "files"

write(dir .. "/flow/start.go", "package flow\n")
vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/flow/start.go"))

notes = {}
files.new "file"
eq("new: titled, and asks below the current file's folder", { asked.kind, asked.opts.title }, { "input", "New file" })
asked.cb "one.go; sub/two.go; keep/"
ok(
  "new: files and the folder exist",
  ops.exists(dir .. "/flow/one.go") and ops.exists(dir .. "/flow/sub/two.go") and ops.is_dir(dir .. "/flow/keep")
)
eq("new: the first file opens", vim.fs.normalize(vim.api.nvim_buf_get_name(0)), dir .. "/flow/one.go")
ok(
  "new: one line says what was made",
  notes[1] ~= nil and notes[1]:find("flow/one.go", 1, true) ~= nil and notes[1]:find("flow/keep", 1, true) ~= nil
)

notes = {}
files.new "file"
asked.cb "one.go"
ok(
  "new: an existing name is reported, not overwritten",
  notes[#notes] ~= nil and notes[#notes]:find("already exists", 1, true) ~= nil
)

files.new "folder"
eq("new folder: titled", asked.opts.title, "New folder")
asked.cb "made/deeper"
ok("new folder: names are folders without a slash", ops.is_dir(dir .. "/flow/made/deeper"))

vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/flow/start.go"))
notes = {}
files.rename()
eq("rename: pre-filled with the current name", asked.opts.default, "start.go")
asked.cb "begin.go"
ok("rename: on disk", ops.exists(dir .. "/flow/begin.go") and not ops.exists(dir .. "/flow/start.go"))
eq("rename: the open buffer follows", vim.fs.normalize(vim.api.nvim_buf_get_name(0)), dir .. "/flow/begin.go")
files.rename()
asked.cb "../x/../y.go"
ok(
  "rename: a bad name is refused with a reason",
  notes[#notes]:find("'.' and '..'", 1, true) ~= nil and ops.exists(dir .. "/flow/begin.go")
)
files.rename()
asked.cb "sub/begin.go"
eq("rename: a name with a slash moves it", vim.fs.normalize(vim.api.nvim_buf_get_name(0)), dir .. "/flow/sub/begin.go")

files.copy()
ok("duplicate: suggests the name", asked.opts.default == "begin_copy.go")
asked.cb(asked.opts.default)
ok(
  "duplicate: the copy exists and opens",
  ops.exists(dir .. "/flow/sub/begin_copy.go")
    and vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == dir .. "/flow/sub/begin_copy.go"
)

local before_delete = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
files.delete()
eq("delete: asks first", asked.kind, "confirm")
ok("delete: and tells where it goes", vim.inspect(asked.lines):find("trash", 1, true) ~= nil)
ok("delete: nothing happened yet", ops.exists(before_delete))
asked.cb()
ok(
  "delete: gone from its place and from the editor",
  not ops.exists(before_delete) and vim.fn.bufnr("^" .. before_delete .. "$") == -1
)
notes = {}
files.undo()
ok("undo: it is back", ops.exists(before_delete) and notes[1] ~= nil and notes[1]:find("Restored", 1, true) ~= nil)
notes = {}
files.undo()
ok("undo: with nothing left it says so", notes[1] ~= nil and notes[1]:find("nothing restored", 1, true) ~= nil)

vim.cmd "enew"
notes = {}
files.rename()
ok("an empty buffer has nothing to rename", notes[1] ~= nil and notes[1]:find("no file here", 1, true) ~= nil)

-- ── the menu ────────────────────────────────────────────────────────────────
local menu = require "menus.files"
eq(
  "menu: prefix and keys",
  { menu.prefix, vim.tbl_map(function(m)
    return m[1]
  end, menu.maps) },
  { "F", { "n", "N", "r", "m", "c", "x", "u", "y", "Y", "t", "o" } }
)

vim.fn.delete(dir, "rf")
print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
