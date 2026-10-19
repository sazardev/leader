-- ── TypeScript / JavaScript actions ──────────────────────────────────────────
-- The package manager comes from the lockfile (pnpm/yarn/bun/npm) and the package.json scripts are used when they
-- exist. Tests run in the editor (langtest: vitest, jest or bun), the typecheck fills the quickfix list, the code
-- actions are vtsls' (imports, fix all), setup files under `S`.
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local MARKERS = { "package.json", ".git" }

---@return string pm, string root
local function package_manager()
  local root = project.root(MARKERS)
  if project.has(root, "pnpm-lock.yaml") then
    return "pnpm", root
  elseif project.has(root, "yarn.lock") then
    return "yarn", root
  elseif project.has(root, "bun.lockb") or project.has(root, "bun.lock") then
    return "bun", root
  end
  return "npm", root
end

---@param root string
---@return string[]
local function scripts(root)
  local content = project.read(root .. "/package.json")
  local ok, pkg = pcall(vim.json.decode, content or "")
  local names = ok and type(pkg) == "table" and type(pkg.scripts) == "table" and vim.tbl_keys(pkg.scripts) or {}
  table.sort(names)
  return names
end

--- Runs the package.json script if it exists; otherwise `fallback` (or warns).
local function script(name, fallback)
  return function()
    local pm, root = package_manager()
    if vim.tbl_contains(scripts(root), name) then
      return terminal.run(("%s run %s"):format(pm, name), root)
    end
    if fallback then
      return terminal.run(fallback, root)
    end
    log.warn(("package.json has no `%s` script"):format(name))
  end
end

local function pick_script()
  local pm, root = package_manager()
  local names = scripts(root)
  if #names == 0 then
    return log.warn "No scripts in package.json"
  end
  vim.ui.select(names, { prompt = pm .. " run" }, function(choice)
    if choice then
      terminal.run(("%s run %s"):format(pm, choice), root)
    end
  end)
end

local function pm_command(sub)
  return function()
    local pm, root = package_manager()
    terminal.run(pm .. " " .. sub, root)
  end
end

--- `add`/`remove` with the packages you type (npm says install/uninstall)
local function pm_packages(verb)
  return function()
    local pm, root = package_manager()
    local sub = pm == "npm" and (verb == "add" and "install" or "uninstall") or verb
    require("utils.modal").input(
      { verb == "add" and "Packages (add -D for dev: -D vitest)" or "Packages to remove" },
      { title = pm .. " " .. sub, confirm = "Run" },
      function(text)
        if text ~= "" then
          terminal.run(("%s %s %s"):format(pm, sub, text), root)
        end
      end
    )
  end
end

--- The errors of `tsc` as quickfix entries (pure): `src/a.ts(12,5): error TS2322: Type … is not assignable…`
---@param lines string[]
---@param root string
---@return table[]
local function tsc_items(lines, root)
  local items = {}
  for _, line in ipairs(lines) do
    local file, lnum, col, kind, msg = line:match "^(.-)%((%d+),(%d+)%): (%a+) (TS%d+: .+)$"
    if file then
      items[#items + 1] = {
        filename = file:sub(1, 1) == "/" and file or (root .. "/" .. file),
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = msg,
        type = kind == "error" and "E" or "W",
      }
    end
  end
  return items
end

--- `c`: the whole project type-checked (tsc --noEmit), the errors in the quickfix list
local function typecheck()
  local pm, root = package_manager()
  local exec = ({ pnpm = { "pnpm", "exec" }, yarn = { "yarn" }, bun = { "bunx" } })[pm] or { "npx", "--no-install" }
  local cmd = vim.list_extend(exec, { "tsc", "--noEmit", "--pretty", "false" })
  log.info "TypeScript: tsc --noEmit…"
  vim.system(cmd, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      local items = tsc_items(vim.split((res.stdout or "") .. "\n" .. (res.stderr or ""), "\n", { plain = true }), root)
      if #items == 0 and res.code ~= 0 then
        return log.warn("TypeScript: tsc failed: " .. (vim.trim(res.stderr or res.stdout or ""):match "[^\n]+" or ""))
      end
      vim.fn.setqflist({}, " ", { title = "tsc", items = items })
      if #items == 0 then
        return log.info "TypeScript: no type errors"
      end
      log.warn(("TypeScript: %d type error%s in the quickfix list"):format(#items, #items == 1 and "" or "s"))
      vim.cmd "botright copen"
    end)
  end)
end

--- A vtsls command on the current position (go to source definition, file references)
local function vtsls(command)
  return function()
    local client = vim.lsp.get_clients({ bufnr = 0, name = "vtsls" })[1]
    if not client then
      return log.warn "TypeScript: vtsls is not running in this buffer"
    end
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    client:exec_cmd({ command = command, arguments = { params.textDocument.uri, params.position } }, { bufnr = 0 })
  end
end

local maps = {
  { "r", "run a package.json script (picker)", pick_script },
  { "d", "dev (script `dev`)", script "dev" },
  { "b", "build (script `build`)", script "build" },
  { "v", "lint (script `lint`, else eslint .)", script("lint", "npx --no-install eslint .") },
  { "c", "typecheck to the quickfix list", typecheck },
  {
    "x",
    "eslint --fix (current file)",
    function()
      local _, root = package_manager()
      terminal.run("npx --no-install eslint --fix " .. vim.fn.shellescape(vim.fn.expand "%:p"), root)
    end,
  },
  { "f", "format", actions.format },
  { "o", "organize imports", actions.code_action "source.organizeImports" },
  { "I", "add missing imports", actions.code_action "source.addMissingImports.ts" },
  { "F", "fix all (TypeScript's quick fixes)", actions.code_action "source.fixAll.ts" },
  { "g", "go to source definition", vtsls "typescript.goToSourceDefinition" },
  { "i", "install dependencies", pm_command "install" },
  { "a", "add packages", pm_packages "add" },
  { "R", "remove packages", pm_packages "remove" },
  { "u", "outdated packages", pm_command "outdated" },
}

vim.list_extend(maps, require("langtest").maps())
vim.list_extend(maps, require("langsetup").maps "typescript")
local M = maps
M.tsc_items = tsc_items -- for the tests
return M
