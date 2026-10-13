-- ── Go actions ───────────────────────────────────────────────────────────────
-- run/build run on the file's DIRECTORY (a Go package is per
-- folder): "." if it hangs under a go.mod, or the single file if there is no module.
-- vet/fix/test run "./..." from the module root.
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

---@return string dir, string? mod_root
local function paths()
  local dir = project.file_dir()
  local gomod = vim.fs.find("go.mod", { path = dir, upward = true })[1]
  return dir, gomod and vim.fs.dirname(gomod)
end

local function target(sub)
  return function()
    local dir, mod_root = paths()
    terminal.run(("go %s %s"):format(sub, mod_root and "." or vim.fn.shellescape(vim.fn.expand "%:t")), dir)
  end
end

local function in_root(cmd)
  return function()
    local dir, mod_root = paths()
    terminal.run(cmd, mod_root or dir)
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

return {
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
  { "m", "go test ./...", in_root "go test ./..." },
  { "R", "go test -race ./...", in_root "go test -race ./..." },
  { "c", "go test -cover ./...", in_root "go test -cover ./..." },
  -- go fix (toolchain modernizers: any, rangeint, minmax, slices*, etc.)
  { "p", "go fix -diff (modernizers preview)", in_root "go fix -diff ./..." },
  { "i", "go fix (apply modernizers)", in_root "go fix ./..." },
  { "g", "go generate ./...", in_root "go generate ./..." },
  { "u", "go get -u + go mod tidy", in_root "go get -u ./... && go mod tidy" },
}
