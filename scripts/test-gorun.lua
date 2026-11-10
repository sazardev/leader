-- Tests for the file-based Go run/build target (utils/gorun.lua): the current
-- file's package runs when it is a main package (each main.go variant runs its
-- own binary), otherwise the module's main is used. Hermetic: Go modules in
-- temporary directories, no gopls or network.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end

local gorun = require "utils.gorun"

-- ── pure ───────────────────────────────────────────────────────────────────
eq("of_src: package main + func main", { gorun.of_src("package main\n\nfunc main() {}\n") }, { "main", true })
eq("of_src: library", { gorun.of_src("package foo\n\nfunc Foo() {}\n") }, { "foo", false })
eq(
  "of_src: func main in a non-main package is reported but never counts as runnable",
  { gorun.of_src("package foo\n\nfunc main() {}\n") },
  { "foo", true }
)
eq(
  "of_src: go:build ignore is not part of the build",
  { gorun.of_src("//go:build ignore\n\npackage main\nfunc main() {}\n") },
  { nil, false }
)
eq("of_src: comment lines don't fake a package", { gorun.of_src("// package main\npackage foo\n") }, { "foo", false })
eq("rel_pkg: root", gorun.rel_pkg("/r", "/r"), ".")
eq("rel_pkg: subfolder", gorun.rel_pkg("/r", "/r/cmd/api"), "./cmd/api")
eq("preferred: root wins", gorun.preferred({ "/r", "/r/cmd/api" }, "/r"), "/r")
eq("preferred: api before worker", gorun.preferred({ "/r/cmd/worker", "/r/cmd/api" }, "/r"), "/r/cmd/api")
eq("preferred: first cmd alphabetically when no favourite", gorun.preferred({ "/r/cmd/zeta", "/r/cmd/alpha" }, "/r"), "/r/cmd/alpha")

-- ── fixtures on disk ───────────────────────────────────────────────────────
local root = vim.fn.tempname()
local function write(rel, lines)
  vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
  vim.fn.writefile(lines, root .. "/" .. rel)
end

-- repo1: root main + library
local r1 = root .. "/r1"
write("r1/go.mod", { "module example.com/r1", "", "go 1.21" })
write("r1/main.go", { "package main", "", "func main() {}", "" })
write("r1/internal/foo/foo.go", { "package foo", "", "func Foo() string { return \"x\" }", "" })

eq("dir_is_main: root with main.go", gorun.dir_is_main(r1), true)
eq("dir_is_main: library dir", gorun.dir_is_main(r1 .. "/internal/foo"), false)
local res = gorun.resolve(r1 .. "/main.go")
eq("resolve: main.go runs its own package", { res.pkg, res.cwd, res.mode }, { ".", r1, "file-main" })
local res_lib = gorun.resolve(r1 .. "/internal/foo/foo.go")
eq(
  "resolve: library file falls back to the root main above it",
  { res_lib.pkg, res_lib.cwd, res_lib.mode },
  { ".", r1, "ancestor-main" }
)

-- repo2: two mains (cmd/api + cmd/worker) + shared library
local r2 = root .. "/r2"
write("r2/go.mod", { "module example.com/r2", "", "go 1.21" })
write("r2/cmd/api/main.go", { "package main", "", "func main() {}", "" })
write("r2/cmd/api/handler.go", { "package main", "", "func handler() {}", "" })
write("r2/cmd/worker/main.go", { "package main", "", "func main() {}", "" })
write("r2/internal/shared/x.go", { "package shared", "", "func X() {}", "" })
local ra = gorun.resolve(r2 .. "/cmd/api/main.go")
eq("resolve: cmd/api/main.go runs ./cmd/api", { ra.pkg, ra.mode }, { "./cmd/api", "file-main" })
local rh = gorun.resolve(r2 .. "/cmd/api/handler.go")
eq(
  "resolve: helper file of a main package (no func main in it) still runs its folder",
  { rh.pkg, rh.mode },
  { "./cmd/api", "file-main" }
)
local rw = gorun.resolve(r2 .. "/cmd/worker/main.go")
eq("resolve: cmd/worker/main.go runs ./cmd/worker", { rw.pkg, rw.mode }, { "./cmd/worker", "file-main" })
local rs = gorun.resolve(r2 .. "/internal/shared/x.go")
eq("resolve: shared library with two mains runs the preferred one", { rs.pkg, rs.mode }, { "./cmd/api", "preferred-main" })

-- unsaved buffer: on-disk library, unsaved main
write("r2/cmd/newapp/app.go", { "package foo", "", "func Foo() {}", "" })
eq(
  "dir_is_main: unsaved buffer counts (just typed func main)",
  gorun.dir_is_main(r2 .. "/cmd/newapp", { path = r2 .. "/cmd/newapp/app.go", text = "package main\n\nfunc main() {}\n" }),
  true
)

-- no module: lone file
local lone = root .. "/lone"
vim.fn.mkdir(lone, "p")
vim.fn.writefile({ "package main", "", "func main() {}", "" }, lone .. "/hello.go")
local rl = gorun.resolve(lone .. "/hello.go")
eq("resolve: without go.mod runs the single file", { rl.pkg, rl.cwd, rl.mode }, { "hello.go", lone, "file" })

-- library-only module: nothing to run
local r3 = root .. "/r3"
write("r3/go.mod", { "module example.com/r3", "", "go 1.21" })
write("r3/foo/foo.go", { "package foo", "", "func Foo() {}", "" })
local res3 = gorun.resolve(r3 .. "/foo/foo.go")
eq("resolve: library-only module has no target", res3, nil)

vim.fn.delete(root, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
