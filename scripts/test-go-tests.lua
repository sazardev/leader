-- Tests for the shared `go test` line (utils/gotest.lua): every test action of <leader>g is verbose by default,
-- settings.go.test is read when the command is built (so the settings panel applies to the next run), and extra
-- flags land BEFORE the package: `go test -v -race ./...`, never `./... -race`.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if got == want then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end

local settings = require "core.settings"
local gotest = require "utils.gotest"

-- the scope is shell-quoted (folders with spaces must survive); the flags never are
local function q(scope)
  return vim.fn.shellescape(scope)
end

local original = vim.deepcopy(settings.go.test)

settings.go.test = { verbose = true }
eq("default: the file's package is verbose", gotest.command(nil, "./cmd/api"), "go test -v " .. q "./cmd/api")
eq("default: the whole module is verbose", gotest.command(nil, "./..."), "go test -v " .. q "./...")
eq("action flags go before the scope", gotest.command({ "-race" }, "./..."), "go test -v -race " .. q "./...")
eq(
  "several action flags keep their order",
  gotest.command({ "-cover", "-timeout=5m" }, "./..."),
  "go test -v -cover -timeout=5m " .. q "./..."
)

settings.go.test = { verbose = false }
eq("verbose off: short form", gotest.command({ "-race" }, "./..."), "go test -race " .. q "./...")

settings.go.test = { verbose = true, args = { "-count=1", "-tags=integration" } }
eq(
  "settings args ride along after the action flags",
  gotest.command({ "-cover" }, "./..."),
  "go test -v -cover -count=1 -tags=integration " .. q "./..."
)

-- a settings table without the key (local.lua replaced it) still defaults to verbose
settings.go.test = {}
eq("missing verbose means verbose", gotest.command(nil, "."), "go test -v " .. q ".")

-- a folder with a space still reaches the shell as one argument
eq("scopes are quoted", gotest.command(nil, "./cmd/my api"), "go test -v './cmd/my api'")

settings.go.test = original
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
