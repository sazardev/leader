-- ── Build with agent: does it build? ────────────────────────────────────────
-- The checks run after the files are written, chosen from the project's manifest (never from the model's text): Go = tidy,
-- gofmt, build, vet, test; Rust = cargo build; Node/Bun = install, tsc, the lint/build/test scripts; Python = uv sync,
-- compileall, ruff and pytest when declared; Flutter/Dart = pub get + analyze. Errors are
-- mapped back to the planned files (`path:line:`) so only those are sent to be fixed.
local M = {}

---@class BuildCheck
---@field label string
---@field cmd string[]
---@field fails_on_output boolean?  gofmt -l: any output is a failure
---@field autofix string[]?          a command that fixes what it reports with no model (gofmt -w)
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

--- The checks for the project at `root` (by its manifest). `prefer`: the package manager STACK.md names (used when no
--- lockfile says otherwise)
---@param root string
---@param prefer string?
---@return BuildCheck[]
function M.checks(root, prefer)
  local has = function(name)
    return vim.uv.fs_stat(root .. "/" .. name) ~= nil
  end
  if has "go.mod" then
    return {
      { label = "go mod tidy", cmd = { "go", "mod", "tidy" } },
      { label = "gofmt -l .", cmd = { "gofmt", "-l", "." }, fails_on_output = true, autofix = { "gofmt", "-w", "." } },
      { label = "go build ./...", cmd = { "go", "build", "./..." } },
      { label = "go vet ./...", cmd = { "go", "vet", "./..." } },
      { label = "go test ./...", cmd = { "go", "test", "./..." } },
    }
  elseif has "Cargo.toml" then
    return { { label = "cargo build", cmd = { "cargo", "build", "--quiet" } } }
  elseif has "pubspec.yaml" then
    local tool = has "lib/main.dart" and "flutter" or "dart"
    return {
      { label = tool .. " pub get", cmd = { tool, "pub", "get" } },
      { label = tool .. " analyze", cmd = { tool, "analyze" } },
    }
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
    out[#out + 1] = { label = pm .. " install", cmd = { pm, "install" } }
    if has "index.html" then
      out[#out + 1] = {
        label = "every id the code looks up exists",
        fn = function()
          local missing = M.missing_ids(web_files(root))
          return #missing == 0, table.concat(missing, "\n")
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
    -- the formatter fixes what the linter reports about format, with no model (once, like gofmt)
    local pkg = require("utils.project").read(root .. "/package.json") or ""
    local formatter = (pkg:find('"@biomejs/biome"', 1, true) and { "biome", "check", "--write", "." })
      or (pkg:find('"prettier"', 1, true) and { "prettier", "--write", "." })
      or nil
    for _, name in ipairs { "lint", "build", "test" } do
      if scripts[name] then
        out[#out + 1] = {
          label = pm .. " run " .. name,
          cmd = { pm, "run", name },
          autofix = name == "lint" and formatter and vim.list_extend(vim.deepcopy(exec), formatter) or nil,
        }
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

--- `path:line` from one line of a tool's output: `file.go:12:3`, `vet: file.go:12`, TypeScript's `file.ts(12,5)`, a bare
--- path alone on its line (gofmt -l)
---@param line string
---@return string?
function M.path_in(line)
  return line:match "%f[%w_%-%.][%.]?/?([%w_%-][%w_%-%./]*%.%w+):%d+"
    or line:match "%f[%w_%-%.][%.]?/?([%w_%-][%w_%-%./]*%.%w+)%(%d+,%d+%)"
    or line:match "^%s*%.?/?([%w_%-%./]+%.%w+)%s*$"
end

--- The planned files the tool output names, with their lines of output (pure)
---@param output string
---@param paths string[] planned paths
---@return table<string, string[]>
function M.blame(output, paths)
  local known = {}
  for _, p in ipairs(paths) do
    known[p] = true
  end
  local out = {}
  for line in (output or ""):gmatch "[^\n]+" do
    local file = M.path_in(line)
    if file and known[file] then
      out[file] = out[file] or {}
      table.insert(out[file], line)
    end
  end
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
