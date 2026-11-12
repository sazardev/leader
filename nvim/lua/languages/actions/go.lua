-- ── Go actions ───────────────────────────────────────────────────────────────
-- run/build run the CURRENT file's package when it can run (a `main` package
-- with `func main`, so each main.go variant — root, cmd/api, cmd/worker… —
-- runs its own binary) and fall back to the module's main otherwise; without
-- a go.mod they run the single file. `test the package of this file` runs
-- `go test ./folder` from the module root (a folder with main.go and its
-- `_test.go` files is tested on its own); vet/fix/test ./... run from the
-- module root. Every test action goes through langtest (`go test -json`):
-- marks on each test line, a failure as a diagnostic, the failures in the
-- quickfix and a statusline chip that stays red until the next run passes.
-- utils/gotest.lua builds the argv and adds settings.go.test.args.
local actions = require "utils.actions"
local langtest = require "langtest"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

---@return string dir, string? mod_root
local function paths()
  local dir = project.file_dir()
  if dir == "" then
    dir = vim.fn.getcwd()
  end
  local gomod = vim.fs.find("go.mod", { path = dir, upward = true })[1]
  return dir, gomod and vim.fs.dirname(gomod)
end

local function target(sub)
  return function()
    local gorun = require "utils.gorun"
    local file = vim.api.nvim_buf_get_name(0)
    local buf_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    local res, err = gorun.resolve(file, buf_text)
    if not res then
      return log.warn(err or "Go: no main package to run")
    end
    terminal.run(("go %s %s"):format(sub, vim.fn.shellescape(res.pkg)), res.cwd)
    if res.note then
      log.info("Go: " .. res.note)
    end
  end
end

local function in_root(cmd)
  return function()
    local dir, mod_root = paths()
    terminal.run(cmd, mod_root or dir)
  end
end

--- `go test` of the CURRENT folder's package (the `main.go` + `*_test.go` folder included): `./cmd/api` from
--- the module root, like `run`, so relative files resolve the same way, and in the folder itself without a go.mod.
local function test_package()
  langtest.run "file"
end

--- `go test` of every package of the module with the action's own flags (`-race`, `-cover`); settings.go.test.args
--- come from utils/gotest.lua.
---@param flags string[]?
local function test_all(flags)
  return function()
    langtest.run("all", nil, { flags = flags })
  end
end

-- go.nvim commands (not loaded in light mode)
local function go_cmd(cmd)
  return function()
    if vim.fn.exists(":" .. cmd:match "^%S+") ~= 2 then
      return log.warn "go.nvim is not loaded (light mode?)"
    end
    vim.cmd(cmd)
  end
end

local maps = {
  { "a", "struct: add json tags (snake_case)", go_cmd "GoAddTag json" },
  { "A", "struct: add json tags + omitempty", go_cmd "GoAddTag json -add-options json=omitempty" },
  { "D", "struct: remove json tags", go_cmd "GoRmTag json" },
  { "s", "struct: fill literal", go_cmd "GoFillStruct" },
  { "e", "if err != nil for the call under the cursor", go_cmd "GoIfErr" },
  { "T", "add test for the function under the cursor", go_cmd "GoAddTest" },
  { "r", "run", target "run" },
  { "b", "build", target "build" },
  {
    "v",
    "lint (golangci-lint, or go vet if missing)",
    function()
      in_root(vim.fn.executable "golangci-lint" == 1 and "golangci-lint run ./..." or "go vet ./...")()
    end,
  },
  {
    "H",
    "lint: gohawk (module audit, quickfix)",
    function()
      local dir, mod_root = paths()
      if vim.fn.executable "gohawk" == 0 then
        return log.warn "gohawk is not installed: go install github.com/kojah/gohawk@latest"
      end
      local root = mod_root or dir
      local cfg = require("core.settings").go.gohawk or {}
      local args = { "gohawk", "-json" }
      vim.list_extend(args, cfg.args or {})
      args[#args + 1] = "./..."
      log.info "gohawk: analyzing the module…"
      vim.system(args, { cwd = root, text = true }, function(out)
        vim.schedule(function()
          if out.code ~= 0 and out.code ~= 3 then
            local err = vim.trim(out.stderr or "")
            return log.warn("gohawk: analysis failed" .. (err ~= "" and (": " .. err) or ""))
          end
          local findings = require("utils.gohawk").parse(out.stdout or "")
          if #findings == 0 then
            return log.info "gohawk: no findings"
          end
          require("utils.gohawk").quickfix(findings)
          log.info(("gohawk: %d finding%s in the quickfix"):format(#findings, #findings == 1 and "" or "s"))
          vim.cmd "copen"
        end)
      end)
    end,
  },
  { "f", "format", actions.format },
  {
    "t",
    "go mod tidy",
    function()
      local _, mod_root = paths()
      if not mod_root then
        return log.warn "No go.mod in the project"
      end
      terminal.run("go mod tidy", mod_root)
    end,
  },
  { "x", "golangci-lint --fix", in_root "golangci-lint run --fix ./..." },
  {
    "M",
    "test under cursor",
    function()
      langtest.run "nearest"
    end,
  },
  { "l", "test the package of this file", test_package },
  { "m", "go test ./...", test_all() },
  { "R", "go test -race ./...", test_all { "-race" } },
  { "c", "go test -cover ./...", test_all { "-cover" } },
  { ".", "test again", langtest.again },
  { "O", "test output", langtest.output },
  -- go fix (toolchain modernizers: any, rangeint, minmax, slices*, etc.)
  { "p", "go fix -diff (modernizers preview)", in_root "go fix -diff ./..." },
  { "i", "go fix (apply modernizers)", in_root "go fix ./..." },
  { "g", "go generate ./...", in_root "go generate ./..." },
  { "u", "go get -u + go mod tidy", in_root "go get -u ./... && go mod tidy" },
}

-- <leader>gS: config files for the project (golangci-lint, Air, Dockerfile, CI, hooks...) — lua/gosetup/
return vim.list_extend(maps, require("gosetup").maps())
