-- ── Build with agent: does it build? ────────────────────────────────────────
-- The checks run after the files are written, chosen from the project's manifest (never from the model's text): Go = tidy,
-- gofmt, build, vet, test; Rust = cargo build; Node/Bun = install, tsc, the lint/build/test scripts; Python = uv sync,
-- compileall, ruff and pytest when declared; Flutter/Dart = pub get + analyze. Errors are
-- mapped back to the planned files (`path:line:`) so only those are sent to be fixed.
-- pnpm 10's blocked dependency build scripts are approved in pnpm-workspace.yaml, with no model (`pnpm_allow_builds`):
-- `onlyBuiltDependencies` on pnpm 10, `allowBuilds` on 11+ (pnpm 12 scaffolds placeholders that are set to true).
-- A missing Playwright browser is a prerequisite: the build asks (Install / Don't install), never downloads silently;
-- a no writes an ADR and the check is waived (`agent.kit.build.install_browsers = false` does not ask).
local M = {}

---@class BuildCheck
---@field label string
---@field cmd string[]
---@field fails_on_output boolean?  gofmt -l: any output is a failure
---@field autofix (string[]|fun(output: string): string[]?)?  a command that fixes what it reports with no model (gofmt -w;
---                                   for tests, the first golden files); a function says which command for that output, or none
---@field mend (fun(root: string, output: string): string|false)?  a fix written here, no command and no model (pnpm's
---                                   blocked build scripts); the string says what it did
---@field waive string?  the prerequisite id a refusal waives ("playwright"); an ADR then skips this check
---@field waived boolean?  the project's ADR waived this check: it does not run (done, not failed)
---@field consent (fun(output: string): { id: string, tool: string, why: string, cmd: string[] }?)?  a missing tool the
---                                   user is asked to install (never downloaded silently)
---@field fn (fun(): boolean, string)?  a check done here, no command (STACK.md against the manifest)

--- Tools a STACK.md table names → the npm package that must then be in package.json
M.NODE_TOOLS = {
  vite = "vite",
  vitest = "vitest",
  typescript = "typescript",
  biome = "@biomejs/biome",
  tailwind = "tailwindcss",
  eslint = "eslint",
  playwright = "@playwright/test",
  react = "react",
  hono = "hono",
  zod = "zod",
  drizzle = "drizzle-orm",
  svelte = "svelte",
  preact = "preact",
  lit = "lit",
  alpine = "alpinejs",
  elysia = "elysia",
}

--- The packages STACK.md's Stack table names that package.json does not list (pure)
---@param stack string STACK.md
---@param package_json string
---@return string[] missing, one per line: "vite (STACK.md: Build | Vite 8 …)"
function M.missing_tools(stack, package_json)
  local table_text = (stack or ""):match "\n## Stack%s*\n(.-)\n## " or ""
  local ok, json = pcall(vim.json.decode, package_json or "")
  if not ok or type(json) ~= "table" then
    return {}
  end
  local deps = {}
  for _, key in ipairs { "dependencies", "devDependencies", "peerDependencies" } do
    for name in pairs(type(json[key]) == "table" and json[key] or {}) do
      deps[name] = true
    end
  end
  local out = {}
  for row in table_text:gmatch "[^\n]+" do
    local choice = row:match "^|[^|]*|([^|]*)|"
    if choice and not row:match "^|%s*%-" then
      local words = " " .. choice:lower():gsub("[^%w]", " ") .. " "
      for word, pkg in pairs(M.NODE_TOOLS) do
        if words:find(" " .. word .. " ", 1, true) and not deps[pkg] and not vim.tbl_contains(out, pkg) then
          out[#out + 1] = pkg
        end
      end
    end
  end
  table.sort(out)
  return out
end

--- `id`s the code looks up that no HTML file defines (pure): `index.html:1: no element with id "x" (src/main.ts:42 …)`
---@param files table<string, string> path → text (the project's .html and script files)
---@return string[]
function M.missing_ids(files)
  local defined, html = {}, nil
  for path, text in pairs(files) do
    if path:match "%.html$" then
      html = html and (path < html and path or html) or path
      for id in text:gmatch "%sid%s*=%s*[\"']([%w_%-:%.]+)[\"']" do
        defined[id] = true
      end
    end
  end
  if not html then
    return {}
  end
  local out, seen = {}, {}
  local paths = vim.tbl_keys(files)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if path:match "%.[jt]sx?$" and not path:match "%.test%.[jt]sx?$" and not path:match "%.spec%.[jt]sx?$" then
      local n = 0
      for line in (files[path] .. "\n"):gmatch "([^\n]*)\n" do
        n = n + 1
        for id in line:gmatch "getElementById%(%s*[\"'`]([%w_%-:%.]+)[\"'`]" do
          if not defined[id] and not seen[id] then
            seen[id] = true
            out[#out + 1] = ('%s:1: no element with id "%s" (%s:%d looks for it)'):format(html, id, path, n)
          end
        end
        -- an id kept in a constant (`const OPEN_SETTINGS_ID = "open-settings"`, `settingsId = '…'`) is looked up too
        for _, id in line:gmatch "([%w_]*[_%l]I[Dd])%s*[:=]%s*[\"'`]([%w_%-]+)[\"'`]" do
          if not defined[id] and not seen[id] then
            seen[id] = true
            out[#out + 1] = ('%s:1: no element with id "%s" (%s:%d looks for it)'):format(html, id, path, n)
          end
        end
        for id in line:gmatch "querySelector%(%s*[\"'`]#([%w_%-]+)[\"'`]" do
          if not defined[id] and not seen[id] then
            seen[id] = true
            out[#out + 1] = ('%s:1: no element with id "%s" (%s:%d looks for it)'):format(html, id, path, n)
          end
        end
      end
    end
  end
  return out
end

local HANDLER_ATTRS =
  { action = true, command = true, cmd = true, op = true, operation = true, handler = true, key = true, fn = true }

--- The handler names the page declares (`data-action="equals"`, `data-command`, `data-op`…) that no script mentions
--- (pure): a button wired to a name the code never handles does nothing, and every test of the logic still passes.
--- `index.html:39: data-action="equals" is handled by no script (they handle: "evaluate", …)`
---@param files table<string, string> path → text (.html and script files)
---@return string[]
function M.unhandled_actions(files)
  local scripts = {}
  for path, text in pairs(files) do
    if path:match "%.[jt]sx?$" and not path:match "%.test%.[jt]sx?$" and not path:match "%.spec%.[jt]sx?$" then
      scripts[#scripts + 1] = text
    end
  end
  if #scripts == 0 then
    return {}
  end
  local code = table.concat(scripts, "\n")
  local out, seen = {}, {}
  local paths = vim.tbl_keys(files)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if path:match "%.html$" then
      local n = 0
      for line in (files[path] .. "\n"):gmatch "([^\n]*)\n" do
        n = n + 1
        for attr, value in line:gmatch "data%-(%a+)%s*=%s*[\"']([%w_%-:%.]+)[\"']" do
          -- a name the code dispatches on (`equals`, `clear`); a digit or a symbol (`7`, `/`) is data parsed generically
          local handler = HANDLER_ATTRS[attr] and value:match "^%a[%w_%-]+%w$" ~= nil and #value >= 3
          if handler and not seen[attr .. value] then
            seen[attr .. value] = true
            local quoted = code:find('"' .. value .. '"', 1, true)
              or code:find("'" .. value .. "'", 1, true)
              or code:find("`" .. value .. "`", 1, true)
              or code:find("%f[%w_]" .. value:gsub("%p", "%%%0") .. "%s*[:(]") -- an object key or a method named so
            if not quoted then
              out[#out + 1] = ('%s:%d: data-%s="%s" is handled by no script: pressing it does nothing (handle that name, or use the name the code handles)'):format(
                path,
                n,
                attr,
                value
              )
            end
          end
        end
      end
    end
  end
  return out
end

--- Stylesheets and modules nothing references (pure): written, never linked or imported. Each line blames the entry
--- (the HTML page) that should load it: `index.html:1: src/styles/base.css is never linked or imported`
---@param files table<string, string> path → text (.html, .css and script files)
---@return string[]
function M.orphans(files)
  local html
  for path in pairs(files) do
    if path:match "%.html$" and (not html or path < html) then
      html = path
    end
  end
  if not html then
    return {}
  end
  local out = {}
  local paths = vim.tbl_keys(files)
  table.sort(paths)
  for _, path in ipairs(paths) do
    local ext = path:match "%.(%w+)$"
    local base = vim.fs.basename(path):gsub("%.%w+$", "")
    local skip = path:match "%.test%."
      or path:match "%.spec%."
      or path:match "%.d%.ts$"
      or path:match "config%."
      or ext == "html"
    if not skip and (ext == "css" or ext == "ts" or ext == "tsx" or ext == "js" or ext == "jsx") then
      local used = false
      for other, text in pairs(files) do
        if
          other ~= path
          and (
            text:find(vim.fs.basename(path), 1, true)
            or text:find("/" .. base .. "[\"'`]")
            or text:find("/" .. base .. "%.js[\"'`]")
          )
        then
          used = true
          break
        end
      end
      if not used then
        out[#out + 1] = ("%s:1: %s is never linked or imported (load it from the page or its entry script)"):format(
          html,
          path
        )
      end
    end
  end
  return out
end

--- The project's HTML and script files (not node_modules, dist or build output)
---@param root string
---@return table<string, string>
local function web_files(root)
  local out = {}
  for name, kind in
    vim.fs.dir(root, {
      depth = 6,
      skip = function(dir)
        local base = vim.fs.basename(dir)
        return base ~= "node_modules" and base ~= "dist" and base ~= "build" and base ~= ".git" and base ~= "coverage"
      end,
    })
  do
    if kind == "file" and (name:match "%.html$" or name:match "%.[jt]sx?$" or name:match "%.css$") then
      out[name] = require("utils.project").read(root .. "/" .. name) or ""
    end
  end
  return out
end

--- Snapshot tests seen for the first time have no golden file yet: they are created by running ONLY those tests with
--- `-update` (what the app draws now becomes the snapshot). Only when missing golden files are the only failure: a test
--- failing for another reason means the app is not right yet, and a snapshot of it would lock the bug in. nil otherwise.
---@param output string
---@return string[]?
function M.golden_update(output)
  if not (output or ""):find "%.golden: no such file" then
    return nil
  end
  local failing, golden = {}, {}
  for name in ("\n" .. output):gmatch "\n%-%-%- FAIL: ([%w_]+)" do -- top-level tests (subtests are indented)
    failing[name] = true
  end
  for name in output:gmatch "testdata/([%w_]+)%.golden: no such file" do
    golden[name] = true
  end
  for name in pairs(failing) do
    if not golden[name] then
      return nil
    end
  end
  local pkgs, seen = {}, {}
  -- `FAIL<tab>pkg<tab>0.05s` (a bare `FAIL` line comes first: the package is the one after the tab)
  for pkg in ("\n" .. output):gmatch "\nFAIL\t([^\t\n%s]+)" do
    if not seen[pkg] then
      seen[pkg] = true
      pkgs[#pkgs + 1] = pkg
    end
  end
  if #pkgs == 0 or next(golden) == nil then
    return nil
  end
  local names = vim.tbl_keys(golden)
  table.sort(names)
  local cmd = { "go", "test" }
  vim.list_extend(cmd, pkgs)
  vim.list_extend(cmd, { "-run", "^(" .. table.concat(names, "|") .. ")$", "-update" })
  return cmd
end

--- Versions a model invented (`go: x@v0.0.0-2025…: invalid version: unknown revision …`): their requires go, and
--- `go mod tidy` puts back the real ones. 0 tokens; nil when no version is unknown.
---@param output string
---@return string[]?
function M.drop_versions(output)
  local cmd, seen = { "go", "mod", "edit" }, {}
  for mod in (output or ""):gmatch "go: ([%w%.%-_/]+)@[^:%s]+: invalid version" do
    if not seen[mod] then
      seen[mod] = true
      cmd[#cmd + 1] = "-droprequire=" .. mod
    end
  end
  for mod in (output or ""):gmatch "go: ([%w%.%-_/]+)@[^:%s]+: reading [^\n]-: 404" do
    if not seen[mod] then
      seen[mod] = true
      cmd[#cmd + 1] = "-droprequire=" .. mod
    end
  end
  return #cmd > 3 and cmd or nil
end

--- Is this path a test file? (Go, JS/TS, Python, Dart, Rust test folders)
---@param path string
---@return boolean
function M.is_test(path)
  return path:match "_test%.go$" ~= nil
    or path:match "%.test%.[jt]sx?$" ~= nil
    or path:match "%.spec%.[jt]sx?$" ~= nil
    or path:match "_test%.py$" ~= nil
    or path:match "/test_[^/]*%.py$" ~= nil
    or path:match "^test_[^/]*%.py$" ~= nil
    or path:match "_test%.dart$" ~= nil
    or path:match "^tests?/" ~= nil
end

--- What a test asserts and what skips it, in the usual frameworks (Go testing/testify/teatest, Jest/Vitest, pytest,
--- Rust, Dart)
local ASSERTS = {
  "t%.Error",
  "t%.Fatal",
  "require%.",
  "assert%.",
  "WaitFor",
  "expect%(",
  "assert%s",
  "assert!%(",
  "assert_eq!%(",
  "assert_ne!%(",
  "should%.",
}
local SKIPS = { "t%.Skip", "%.skip%(", "xit%(", "xdescribe%(", "@pytest%.mark%.skip", "#%[ignore%]", "skip:%s*true" }

---@param text string
---@param patterns string[]
---@return integer
local function count(text, patterns)
  local n = 0
  for _, pat in ipairs(patterns) do
    n = n + select(2, text:gsub(pat, ""))
  end
  return n
end

--- Does the new version of a test check less than the old one? (fewer assertions or waits, a new skip) → why, else nil
---@param old string
---@param new string
---@return string?
function M.weakened(old, new)
  local before, after = count(old or "", ASSERTS), count(new or "", ASSERTS)
  if after < before then
    return ("it removes %d assertion%s or wait%s"):format(
      before - after,
      before - after == 1 and "" or "s",
      before - after == 1 and "" or "s"
    )
  end
  if count(new or "", SKIPS) > count(old or "", SKIPS) then
    return "it skips a test"
  end
end

---@param path string
---@return boolean
function M.is_manifest(path)
  return vim.tbl_contains(M.MANIFESTS, path)
end

M.MANIFESTS = { "package.json", "go.mod", "Cargo.toml", "pyproject.toml", "requirements.txt", "pubspec.yaml" }

--- The package manager STACK.md names in its Stack table (what to use before any lockfile exists)
---@param stack string?
---@return string?
function M.package_manager_hint(stack)
  local row = (stack or ""):match "\n|%s*Package manager%s*|([^|\n]*)|"
  local word = row and row:lower():match "(%a+)"
  return ({ bun = "bun", pnpm = "pnpm", npm = "npm", yarn = "yarn" })[word or ""]
end

--- The manifest the plan wrote, when an error names no file (a tool that does not run is a missing dependency)
---@param paths string[]
---@return string?
function M.manifest_of(paths)
  local planned = {}
  for _, p in ipairs(paths) do
    planned[p] = true
  end
  for _, m in ipairs(M.MANIFESTS) do
    if planned[m] then
      return m
    end
  end
end

--- pnpm 10 refuses to run a dependency's build scripts until they are approved (`ERR_PNPM_IGNORED_BUILDS`): the
--- package names it says, without their versions (pure; nil when that is not the failure)
---@param output string
---@return string[]?
function M.pnpm_ignored(output)
  local text = (output or ""):gsub("\27%[[%d;?]*%a", "")
  if not text:find("ERR_PNPM_IGNORED_BUILDS", 1, true) then
    return nil
  end
  local key = "Ignored build scripts:"
  local at = text:find(key, 1, true)
  if not at then
    return nil
  end
  local lines = vim.split(text:sub(at + #key), "\n", { plain = true })
  local block = { lines[1] or "" } -- pnpm wraps the list after a comma
  for i = 2, #lines do
    if not block[#block]:match ",%s*$" then
      break
    end
    if lines[i]:match "^%s*$" or lines[i]:find("help:", 1, true) then
      break
    end
    block[#block + 1] = lines[i]
  end
  local names, seen = {}, {}
  for entry in table.concat(block, " "):gmatch "[^,%s]+" do
    local name = entry:match "^(@[^@/]+/[^@]+)@[^@]+$" or entry:match "^([^@]+)@[^@]+$" or entry
    if name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  return #names > 0 and names or nil
end

--- The pnpm major (`pnpm --version`), nil when it cannot be read (tests pass their own)
---@param root string
---@return integer?
function M.pnpm_major(root)
  local ok, res = pcall(function()
    return vim.system({ "pnpm", "--version" }, { cwd = root, text = true, timeout = 5000 }):wait()
  end)
  if not ok or type(res) ~= "table" then
    return nil
  end
  return tonumber(vim.trim((res.stdout or "") .. " " .. (res.stderr or "")):match "^v?(%d+)")
end

---@param name string
---@return string
local function unquote(name)
  return (name or ""):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
end

---@param name string
---@return string
local function yaml_item(name)
  return name:match "^@" and ('"' .. name .. '"') or name -- a plain scalar cannot start with @
end

--- The `onlyBuiltDependencies` block (pnpm 10): where it starts, the names it has, its last line and its indentation.
--- nil when there is no block; false when it is flow style (not ours to merge line by line)
---@param lines string[]
---@return integer|false|nil at, table<string, boolean>? names, integer? last, string? indent
local function pnpm_block(lines)
  local at
  for i, line in ipairs(lines) do
    if line:match "^onlyBuiltDependencies:%s*$" or line:match "^onlyBuiltDependencies:%s*#.*$" then
      at = i
      break
    end
    if line:match "^onlyBuiltDependencies:" then
      return false
    end
  end
  if not at then
    return nil
  end
  local names, last, indent = {}, at, nil
  for j = at + 1, #lines do
    local line = lines[j]
    if line:match "^%s+%-" then
      indent = indent or line:match "^(%s+)%-"
      local name = unquote(line:match "^%s+%-%s*([^#%s]+)")
      if name ~= "" then
        names[name] = true
      end
      last = j
    elseif not (line:match "^%s*$" or line:match "^%s*#") then
      break
    end
  end
  return at, names, last, indent or "  "
end

--- The `allowBuilds` block (pnpm 11+): where it starts, its entries (line and value), its last line and indentation.
--- nil when there is no block; false when it is flow style
---@param lines string[]
---@return integer|false|nil at, table<string, { line: integer, value: string }>? entries, integer? last, string? indent
local function allow_block(lines)
  local at
  for i, line in ipairs(lines) do
    if line:match "^allowBuilds:%s*$" or line:match "^allowBuilds:%s*#.*$" then
      at = i
      break
    end
    if line:match "^allowBuilds:" then
      return false
    end
  end
  if not at then
    return nil
  end
  local entries, last, indent = {}, at, nil
  for j = at + 1, #lines do
    local line = lines[j]
    if line:match "^[^%s#]" then
      break -- a new top-level key (onlyBuiltDependencies, packages…)
    elseif line:match "^%s*#" or line:match "^%s*$" then
      -- a comment or a blank line inside the block: keep looking for entries
    elseif line:match "^%s+%-" then
      break -- a list where a map belongs
    else
      local key, value = line:match "^%s*(.*):%s*(.-)%s*$"
      if not key or key == "" then
        break
      end
      entries[unquote(key)] = { line = j, value = value }
      indent = indent or line:match "^(%s+)"
      last = j
    end
  end
  return at, entries, last, indent or "  "
end

---@param lines string[]
---@param names string[]
---@return string[] changed
local function write_allow(lines, names)
  local at, entries, last, indent = allow_block(lines)
  if at == false then
    return {}
  end
  local added, changed = {}, {}
  for _, name in ipairs(names) do
    local entry = entries and entries[name]
    if entry then
      if entry.value:find("set this to true or false", 1, true) then
        lines[entry.line] = lines[entry.line]:gsub("set this to true or false", "true")
        changed[#changed + 1] = name
      end
      -- `true` is approved already; `false` is an explicit deny and stays
    else
      added[#added + 1] = name
    end
  end
  if at then
    for _, name in ipairs(added) do
      last = last + 1
      table.insert(lines, last, indent .. yaml_item(name) .. ": true")
      changed[#changed + 1] = name
    end
  else
    if #lines > 0 and lines[#lines] ~= "" then
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "allowBuilds:"
    for _, name in ipairs(added) do
      lines[#lines + 1] = "  " .. yaml_item(name) .. ": true"
      changed[#changed + 1] = name
    end
  end
  return changed
end

---@param lines string[]
---@param names string[]
---@return string[] added
local function write_legacy(lines, names)
  local at, existing, last, indent = pnpm_block(lines)
  if at == false then
    return {}
  end
  local added = {}
  for _, name in ipairs(names) do
    if not (existing and existing[name]) then
      added[#added + 1] = name
    end
  end
  if #added == 0 then
    return {}
  end
  if at then
    for _, name in ipairs(added) do
      last = last + 1
      table.insert(lines, last, indent .. "- " .. yaml_item(name))
    end
  else
    if #lines > 0 and lines[#lines] ~= "" then
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "onlyBuiltDependencies:"
    for _, name in ipairs(added) do
      lines[#lines + 1] = "  - " .. yaml_item(name)
    end
  end
  return added
end

--- pnpm blocks the build scripts of the dependencies it installs until they are approved. Writes the packages pnpm
--- named into pnpm-workspace.yaml, creating the file and keeping what is already there: no model, 0 tokens.
--- pnpm 10 uses `onlyBuiltDependencies` (a list); pnpm 11+ uses `allowBuilds` (a map). pnpm 12 scaffolds the blocked
--- packages as `name: set this to true or false`, so those placeholders become `true`; an explicit `false` stays.
--- Returns what it changed, or false when there is nothing to add (or `agent.kit.build.auto_build_scripts` is off).
---@param root string
---@param output string
---@param major integer? the pnpm major (tests); read from `pnpm --version` when nil
---@return string|false
function M.pnpm_allow_builds(root, output, major)
  local names = M.pnpm_ignored(output)
  if not names then
    return false
  end
  local kit = require("core.settings").agent.kit
  if kit and kit.build and kit.build.auto_build_scripts == false then
    return false
  end
  local path = root .. "/pnpm-workspace.yaml"
  local lines = vim.split(require("utils.project").read(path) or "", "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  major = major or M.pnpm_major(root)
  local modern = major and major >= 11
  if not major then -- the version could not be read: the file says which generation made it
    for _, line in ipairs(lines) do
      if line:match "^allowBuilds:" then
        modern = true
        break
      end
    end
  end
  local changed = modern and write_allow(lines, names) or write_legacy(lines, names)
  if #changed == 0 then
    return false
  end
  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
  pcall(vim.uv.fs_chmod, path, 420) -- 0644: a project file, not a private one (io.open honors a 077 umask)
  return ("pnpm-workspace.yaml: %s (%s)"):format(
    table.concat(changed, ", "),
    modern and "allowBuilds" or "onlyBuiltDependencies"
  )
end

--- The checks for the project at `root` (by its manifest). `prefer`: the package manager STACK.md names (used when no
--- lockfile says otherwise)
---@param root string
---@param prefer string?
---@return BuildCheck[]
local function kind_checks(root, prefer)
  local has = function(name)
    return vim.uv.fs_stat(root .. "/" .. name) ~= nil
  end
  if has "go.mod" then
    return {
      { label = "go mod tidy", cmd = { "go", "mod", "tidy" }, autofix = M.drop_versions },
      { label = "gofmt -l .", cmd = { "gofmt", "-l", "." }, fails_on_output = true, autofix = { "gofmt", "-w", "." } },
      { label = "go build ./...", cmd = { "go", "build", "./..." } },
      { label = "go vet ./...", cmd = { "go", "vet", "./..." } },
      { label = "go test ./...", cmd = { "go", "test", "./..." }, autofix = M.golden_update },
    }
  elseif has "Cargo.toml" then
    local out = { { label = "cargo build", cmd = { "cargo", "build", "--quiet" } } }
    if has "tests" then -- a project that has tests runs them: "it builds" was all that was checked
      out[#out + 1] = { label = "cargo test", cmd = { "cargo", "test", "--quiet" } }
    end
    return out
  elseif has "pubspec.yaml" then
    local tool = has "lib/main.dart" and "flutter" or "dart"
    local out = {
      { label = tool .. " pub get", cmd = { tool, "pub", "get" } },
      { label = tool .. " analyze", cmd = { tool, "analyze" } },
    }
    -- analyze says the code compiles, not that it works: a project with tests runs them (a repair once left seven failing)
    if has "test" then
      out[#out + 1] = { label = tool .. " test", cmd = { tool, "test" } }
    end
    return out
  elseif has "package.json" then
    local pm = (has "pnpm-lock.yaml" and "pnpm")
      or ((has "bun.lock" or has "bun.lockb") and "bun")
      or (has "yarn.lock" and "yarn")
      or (has "package-lock.json" and "npm")
      or prefer
      or "npm"
    local scripts = M.scripts(root)
    if pm == "npm" and scripts.packageManager and scripts.packageManager:match "^bun" then
      pm = "bun"
    end
    -- only the project's own binaries (`bunx tsc` would download an unrelated package called tsc)
    local exec = ({
      bun = { "bun", "run" },
      pnpm = { "pnpm", "exec" },
      npm = { "npx", "--no-install" },
      yarn = { "yarn" },
    })[pm]
    local out = {}
    local stack = require("utils.project").read(root .. "/STACK.md")
    if stack then
      out[#out + 1] = {
        label = "package.json has STACK.md's tools",
        fn = function()
          local missing = M.missing_tools(stack, require("utils.project").read(root .. "/package.json") or "")
          if #missing == 0 then
            return true, ""
          end
          return false,
            "package.json lacks what STACK.md's Stack table names: "
              .. table.concat(missing, ", ")
              .. ". Add them (and the scripts that use them: dev, build, test) to package.json."
        end,
      }
    end
    out[#out + 1] = {
      label = pm .. " install",
      cmd = { pm, "install" },
      mend = pm == "pnpm" and M.pnpm_allow_builds or nil,
    }
    if has "index.html" then
      out[#out + 1] = {
        label = "every id the code looks up exists",
        fn = function()
          local missing = M.missing_ids(web_files(root))
          return #missing == 0, table.concat(missing, "\n")
        end,
      }
      out[#out + 1] = {
        label = "every control the page declares is handled",
        fn = function()
          local unhandled = M.unhandled_actions(web_files(root))
          return #unhandled == 0, table.concat(unhandled, "\n")
        end,
      }
      out[#out + 1] = {
        label = "every stylesheet and module is used",
        fn = function()
          local unused = M.orphans(web_files(root))
          return #unused == 0, table.concat(unused, "\n")
        end,
      }
    end
    if has "tsconfig.json" then
      out[#out + 1] = {
        label = "tsc --noEmit",
        cmd = vim.list_extend(vim.deepcopy(exec), { "tsc", "--noEmit", "--pretty", "false" }),
      }
    end
    -- the e2e webServer runs `pnpm run preview`: Astro's `preview` must be `astro preview`, not a dev server that
    -- never exits (measured: a fix round changed it to `astro dev` and Playwright reported "webServer exited early")
    if has "astro.config.mjs" then
      out[#out + 1] = {
        label = "preview script",
        fn = function()
          local problem = M.preview_problem(require("utils.project").read(root .. "/package.json") or "")
          return problem == nil, problem or ""
        end,
      }
    end
    -- the formatter fixes what the linter reports about format, with no model (once, like gofmt)
    local pkg = require("utils.project").read(root .. "/package.json") or ""
    local formatter = (pkg:find('"@biomejs/biome"', 1, true) and { "biome", "check", "--write", "." })
      or (pkg:find('"prettier"', 1, true) and { "prettier", "--write", "." })
      or nil
    --- The tool that fixes this script's failure with no model, or nil
    ---@param name string
    ---@return string[]|fun(output: string): string[]?
    local function fixer_for(name)
      if name == "lint" then
        return formatter and vim.list_extend(vim.deepcopy(exec), formatter) or nil
      end
      return nil
    end
    local pw_cmd = pm == "bun" and { "bunx", "playwright", "install" }
      or vim.list_extend(vim.deepcopy(exec), { "playwright", "install" })
    --- A missing Playwright browser is a prerequisite, not a code bug: the build asks before downloading it
    ---@param label string
    ---@return fun(output: string): { id: string, tool: string, why: string, cmd: string[] }?
    local function playwright_consent(label)
      return function(output)
        output = output or ""
        if not output:find("Executable doesn't exist at", 1, true) or not output:find("ms-playwright", 1, true) then
          return nil
        end
        local kit = require("core.settings").agent.kit
        if kit and kit.build and kit.build.install_browsers == false then
          return nil
        end
        local browser = output:match "ms%-playwright/([%a]+)"
        local tool = "Playwright's browser"
        if browser then
          tool = tool .. " (" .. browser:gsub("^%l", string.upper) .. ")"
        end
        return {
          id = "playwright",
          tool = tool,
          why = ("the `%s` check runs browser tests and needs it"):format(label),
          cmd = vim.deepcopy(pw_cmd),
        }
      end
    end
    for _, name in ipairs { "lint", "build", "test" } do
      if scripts[name] then
        local check = {
          label = pm .. " run " .. name,
          cmd = { pm, "run", name },
          autofix = fixer_for(name),
        }
        if name == "test" then
          check.waive = "playwright"
          check.consent = playwright_consent(check.label)
        end
        out[#out + 1] = check
      end
    end
    return out
  elseif has "pyproject.toml" or has "requirements.txt" then
    local uv = has "uv.lock" or vim.fn.executable "uv" == 1
    local run = uv and { "uv", "run" } or {}
    local out = {}
    if uv and has "pyproject.toml" then
      out[#out + 1] = { label = "uv sync", cmd = { "uv", "sync" } }
    end
    out[#out + 1] =
      { label = "compileall", cmd = vim.list_extend(vim.deepcopy(run), { "python", "-m", "compileall", "-q", "." }) }
    local manifest = (require("utils.project").read(root .. "/pyproject.toml") or "")
      .. (require("utils.project").read(root .. "/requirements.txt") or "")
    if manifest:find("ruff", 1, true) then
      out[#out + 1] = { label = "ruff check", cmd = vim.list_extend(vim.deepcopy(run), { "ruff", "check", "." }) }
    end
    if manifest:find("pytest", 1, true) then
      out[#out + 1] = { label = "pytest", cmd = vim.list_extend(vim.deepcopy(run), { "pytest", "-q" }) }
    end
    return out
  end
  return {}
end

--- The project's own source files, path → text (small ones, at most 600), for the checks that read code
---@param root string
---@return table<string, string>
local function source_texts(root)
  local decls = require "agent.kit.decls"
  local read = require("utils.project").read
  local out, count = {}, 0
  for _, p in ipairs(require("agent.kit.snapshot").list_files(root)) do
    if count >= 600 then
      break
    end
    if decls.is_source(p) then
      local stat = vim.uv.fs_stat(root .. "/" .. p)
      if stat and stat.size <= 96 * 1024 then
        out[p], count = read(root .. "/" .. p) or "", count + 1
      end
    end
  end
  return out
end

--- Public types declared in two files: layers written apart that each wrote the same thing (agent/kit/decls.lua).
--- A pure function of the sources so it is tested without a project
---@param sources table<string, string>
---@return boolean ok, string message
function M.duplicate_types(sources)
  local decls = require "agent.kit.decls"
  local found = decls.duplicates(sources)
  if #found == 0 then
    return true, ""
  end
  return false, table.concat(decls.describe_duplicates(found), "\n")
end

--- The checks of a project, chosen from its manifest, and the ones every project gets: no public type declared twice
---@param root string
---@param prefer string?
---@return BuildCheck[]
function M.checks(root, prefer)
  local list = kind_checks(root, prefer)
  if #list > 0 then
    list[#list + 1] = {
      label = "no type is declared twice",
      fn = function()
        return M.duplicate_types(source_texts(root))
      end,
    }
  end
  return list
end

--- package.json's scripts (and its packageManager field), {} when unreadable
---@param root string
---@return table<string, string>
function M.scripts(root)
  local ok, json = pcall(vim.json.decode, require("utils.project").read(root .. "/package.json") or "")
  if not ok or type(json) ~= "table" then
    return {}
  end
  local out = type(json.scripts) == "table" and vim.deepcopy(json.scripts) or {}
  out.packageManager = json.packageManager
  return out
end

--- The e2e webServer runs `pnpm run preview`: an Astro project's `preview` must be `astro preview`. A dev server
--- (`astro dev`) never exits, so Playwright reports "webServer exited early" and the tests never run. Pure.
---@param package_json string?
---@return string?
function M.preview_problem(package_json)
  local ok, pkg = pcall(vim.json.decode, package_json or "")
  if not ok or type(pkg) ~= "table" or type(pkg.scripts) ~= "table" then
    return nil
  end
  local preview = pkg.scripts.preview
  if preview == nil or preview == "astro preview" or type(preview) ~= "string" then
    return nil
  end
  return ("package.json `preview` is `%s`: it must be `astro preview` (the e2e webServer runs `pnpm run preview`; a dev server never exits)."):format(
    preview
  )
end

--- `path:line` from one line of a tool's output: `file.go:12:3`, `vet: file.go:12`, TypeScript's `file.ts(12,5)`, a bare
--- path alone on its line (gofmt -l)
---@param line string
---@return string?
function M.path_in(line)
  return line:match "%f[%w_%-%.][%.]?/?([%w_%-][%w_%-%./]*%.%w+):%d+"
    or line:match "%f[%w_%-%.][%.]?/?([%w_%-][%w_%-%./]*%.%w+)%(%d+,%d+%)"
    or line:match "^%s*%.?/?([%w_%-%./]+%.%w+)%s*$"
end

--- The planned files the tool output names, with their lines of output (pure). `module` (go.mod's module path) maps
--- `go test`'s package-relative names back to the project
---@param output string
---@param paths string[] planned paths
---@param module string?
---@return table<string, string[]>
function M.blame(output, paths, module)
  local known, by_base = {}, {}
  for _, p in ipairs(paths) do
    known[p] = true
    local base = vim.fs.basename(p)
    by_base[base] = by_base[base] or {}
    table.insert(by_base[base], p)
  end
  local out = {}
  local function add(file, line)
    out[file] = out[file] or {}
    table.insert(out[file], line)
  end
  -- `go test` names files relative to their package (`app_test.go:46:`) and says the package after them
  -- (`FAIL<tab>module/internal/ui`): those wait for it; a name that fits one planned file only needs no package
  local pending = {}
  local function settle(pkg)
    local dir = pkg and module and pkg:sub(1, #module) == module and pkg:sub(#module + 2) or nil
    for _, item in ipairs(pending) do
      local candidates = by_base[vim.fs.basename(item.file)] or {}
      local hit = dir
        and known[(dir ~= "" and (dir .. "/") or "") .. item.file]
        and ((dir ~= "" and (dir .. "/") or "") .. item.file)
      if not hit and #candidates == 1 then
        hit = candidates[1]
      end
      if hit then
        add(hit, item.line)
      end
    end
    pending = {}
  end
  for line in (output or ""):gmatch "[^\n]+" do
    local pkg = line:match "^FAIL%s+(%S+)%s" or line:match "^FAIL%s+(%S+)$" or line:match "^ok%s+(%S+)%s"
    if pkg and pkg ~= "FAIL" then
      settle(pkg)
    else
      local file = M.path_in(line)
      if file and known[file] then
        add(file, line)
      elseif file then
        pending[#pending + 1] = { file = file, line = line }
      end
    end
  end
  settle(nil)
  return out
end

--- Files the tool output names that are not planned (a leftover from an older build, a file edited by hand)
---@param output string
---@param paths string[]
---@return string[]
function M.outside(output, paths)
  local known, seen, out = {}, {}, {}
  for _, p in ipairs(paths) do
    known[p] = true
  end
  for line in (output or ""):gmatch "[^\n]+" do
    local file = M.path_in(line)
    if file and not known[file] and not seen[file] and not line:match "^%s*%.?/?[%w_%-%./]+%.%w+%s*$" then
      seen[file] = true
      out[#out + 1] = file
    end
  end
  return out
end

--- Runs the checks in order; `step(i, ok, output)` after each; `done(ok, output_of_the_failing_one)` at the end
---@param root string
---@param checks BuildCheck[]
---@param step fun(i: integer, ok: boolean, output: string)
---@param done fun(ok: boolean, output: string?, check: BuildCheck?)
function M.run(root, checks, step, done)
  local i = 0
  local function next_check()
    i = i + 1
    local check = checks[i]
    if not check then
      return done(true)
    end
    if check.waived then -- the user declined this prerequisite and an ADR records it: done, not failed
      step(i, true, "waived")
      return next_check()
    end
    if check.fn then
      local ok, output = check.fn()
      step(i, ok, output)
      if not ok then
        return done(false, output, check)
      end
      return next_check()
    end
    if vim.fn.executable(check.cmd[1]) ~= 1 then
      step(i, false, check.cmd[1] .. " is not installed")
      return done(false, check.cmd[1] .. " is not installed", check)
    end
    vim.system(check.cmd, { cwd = root, text = true, timeout = 300000 }, function(res)
      vim.schedule(function()
        -- without terminal colors: the feed shows it and the model reads it
        local output = vim.trim(((res.stdout or "") .. "\n" .. (res.stderr or "")):gsub("\27%[[%d;?]*[%a]", ""))
        local ok = res.code == 0 and not (check.fails_on_output and output ~= "")
        step(i, ok, output)
        if not ok then
          return done(false, output, check)
        end
        next_check()
      end)
    end)
  end
  next_check()
end

return M
