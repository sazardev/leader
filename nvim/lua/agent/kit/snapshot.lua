-- ── Project kit: what the project looks like ─────────────────────────────────
-- The facts AGENTS.md is written from, gathered without a model: the files (git ls-files, else a walk), the languages they
-- are in, the manifests (go.mod, package.json, pubspec.yaml…), the commands those imply, the README's start and the kit
-- documents already there. `collect` does the IO; `languages`, `commands` and `tree` are pure (scripts/test-kit.lua).
local M = {}

local SKIP = {
  [".git"] = true,
  node_modules = true,
  vendor = true,
  dist = true,
  build = true,
  target = true,
  [".dart_tool"] = true,
  [".next"] = true,
  [".venv"] = true,
  venv = true,
  __pycache__ = true,
  coverage = true,
  [".idea"] = true,
  [".vscode"] = true,
}

--- Files whose head tells what the project is built with
M.MANIFESTS = {
  "go.mod",
  "go.work",
  "package.json",
  "pnpm-workspace.yaml",
  "turbo.json",
  "nx.json",
  "pubspec.yaml",
  "melos.yaml",
  "Cargo.toml",
  "pyproject.toml",
  "requirements.txt",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "settings.gradle.kts",
  "composer.json",
  "Gemfile",
  "Makefile",
  "Dockerfile",
  "docker-compose.yml",
  "compose.yaml",
  ".golangci.yml",
  "tsconfig.json",
  "deno.json",
  "deno.jsonc",
  "Package.swift",
  "Rakefile",
}

local LANGS = {
  go = "Go",
  ts = "TypeScript",
  tsx = "TypeScript",
  js = "JavaScript",
  jsx = "JavaScript",
  mjs = "JavaScript",
  dart = "Dart",
  rs = "Rust",
  py = "Python",
  java = "Java",
  kt = "Kotlin",
  kts = "Kotlin",
  swift = "Swift",
  rb = "Ruby",
  php = "PHP",
  cs = "C#",
  c = "C",
  h = "C",
  cpp = "C++",
  lua = "Lua",
  sql = "SQL",
  svelte = "Svelte",
  vue = "Vue",
  templ = "templ",
  css = "CSS",
  scss = "CSS",
  html = "HTML",
  ex = "Elixir",
  exs = "Elixir",
}

---@class KitFacts
---@field root string
---@field name string
---@field files string[]        relative paths
---@field languages { name: string, files: integer }[]
---@field manifests table<string, string>   name → head of the file
---@field scripts table<string, string>     package.json scripts
---@field targets string[]      Makefile targets
---@field readme string?
---@field docs table<string, string>        kit documents already there (file → text)
---@field commands { label: string, cmd: string }[]
---@field deno_tasks table<string, string>
---@field composer_scripts table<string, string>

--- Languages by number of files, most used first
---@param files string[]
---@return { name: string, files: integer }[]
function M.languages(files)
  local count = {}
  for _, f in ipairs(files) do
    local lang = LANGS[(f:match "%.([%w]+)$" or ""):lower()]
    if lang then
      count[lang] = (count[lang] or 0) + 1
    end
  end
  local out = {}
  for name, n in pairs(count) do
    out[#out + 1] = { name = name, files = n }
  end
  table.sort(out, function(a, b)
    return a.files > b.files or (a.files == b.files and a.name < b.name)
  end)
  return out
end

--- The Makefile's own targets (not pattern rules, variables nor dot-targets)
---@param text string
---@return string[]
function M.make_targets(text)
  local out, seen = {}, {}
  for line in (text or ""):gmatch "[^\n]+" do
    local name = line:match "^([%w][%w_%-/]*)%s*:[^=]" or line:match "^([%w][%w_%-/]*)%s*:$"
    if name and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

---@param files string[]
---@return table<string, boolean>
local function set(files)
  local s = {}
  for _, f in ipairs(files) do
    s[f] = true
  end
  return s
end

--- What to run to build, test, lint and format: the Makefile's targets win, then what the manifests imply
---@param facts { files: string[], scripts: table<string, string>?, targets: string[]?, manifests: table<string, string>?, deno_tasks: table?, composer_scripts: table? }
---@return { label: string, cmd: string }[]
function M.commands(facts)
  local has = set(facts.files)
  local out, labels = {}, {}
  local function add(label, cmd)
    if not labels[label] then
      labels[label] = true
      out[#out + 1] = { label = label, cmd = cmd }
    end
  end
  local targets = set(facts.targets or {})
  for _, t in ipairs {
    "install",
    "setup",
    "deps",
    "build",
    "test",
    "lint",
    "fmt",
    "format",
    "run",
    "dev",
    "check",
    "generate",
  } do
    if targets[t] then
      local label = ({ fmt = "format", setup = "install", deps = "install" })[t] or t
      add(label, "make " .. t)
    end
  end
  local manifests = facts.manifests or {}
  --- does a manifest name this tool (a dependency, a [tool.x] table…)?
  local function declares(word)
    for _, text in pairs(manifests) do
      if text:find(word, 1, true) then
        return true
      end
    end
    return false
  end

  local scripts = facts.scripts or {}
  if has["package.json"] then
    local pm = (has["pnpm-lock.yaml"] and "pnpm")
      or (has["yarn.lock"] and "yarn")
      or ((has["bun.lockb"] or has["bun.lock"]) and "bun")
      or "npm"
    add("install", pm == "npm" and (has["package-lock.json"] and "npm ci" or "npm install") or (pm .. " install"))
    for _, s in ipairs { "dev", "start", "build", "test", "lint", "format", "typecheck", "check" } do
      if scripts[s] then
        -- `<pm> run <script>` is always the script: `bun test` would be bun's own runner, `npm build` is not a script
        add(s, (s == "test" and pm ~= "bun") and (pm .. " test") or (pm .. " run " .. s))
      end
    end
  end
  if has["deno.json"] or has["deno.jsonc"] then
    for _, t in ipairs { "dev", "start", "build", "test" } do
      if (facts.deno_tasks or {})[t] then
        add(t, "deno task " .. t)
      end
    end
    add("test", "deno test")
    add("lint", "deno lint")
    add("format", "deno fmt")
  end
  if has["go.mod"] or has["go.work"] then
    add("install", "go mod download")
    add("build", "go build ./...")
    add("test", "go test ./...")
    add("lint", (has[".golangci.yml"] or has[".golangci.yaml"]) and "golangci-lint run" or "go vet ./...")
    add("format", "gofmt -w .")
  end
  if has["pubspec.yaml"] then
    local flutter = false
    for _, f in ipairs(facts.files) do
      if f:match "^lib/main%.dart$" or f:match "^android/" or f:match "^ios/" then
        flutter = true
        break
      end
    end
    local tool = flutter and "flutter" or "dart"
    add("install", tool .. " pub get")
    add("test", tool .. " test")
    add("lint", tool .. " analyze")
    add("format", "dart format .")
    if flutter then
      add("run", "flutter run")
    end
    if declares "build_runner" then
      add("generate", "dart run build_runner build --delete-conflicting-outputs")
    end
  end
  if has["Cargo.toml"] then
    add("install", "cargo fetch")
    add("build", "cargo build")
    add("test", "cargo test")
    add("lint", "cargo clippy --all-targets -- -D warnings")
    add("format", "cargo fmt")
  end
  if has["pyproject.toml"] or has["requirements.txt"] then
    -- the runner from the lockfile; the tools only when a manifest declares them (no pytest/ruff guessed)
    local run = (has["uv.lock"] and "uv run ")
      or (has["poetry.lock"] and "poetry run ")
      or (has["pdm.lock"] and "pdm run ")
      or ""
    add(
      "install",
      (has["uv.lock"] and "uv sync")
        or (has["poetry.lock"] and "poetry install")
        or (has["pdm.lock"] and "pdm install")
        or (has["requirements.txt"] and "pip install -r requirements.txt")
        or "pip install -e ."
    )
    if declares "pytest" then
      add("test", run .. "pytest")
    end
    if declares "ruff" then
      add("lint", run .. "ruff check .")
      add("format", run .. "ruff format .")
    end
    if declares "mypy" then
      add("typecheck", run .. "mypy .")
    elseif declares "pyright" then
      add("typecheck", run .. "pyright")
    end
  end
  if has["pom.xml"] then
    local mvn = has.mvnw and "./mvnw" or "mvn"
    add("build", mvn .. " -q package")
    add("test", mvn .. " -q test")
  elseif has["build.gradle"] or has["build.gradle.kts"] then
    local gradle = has.gradlew and "./gradlew" or "gradle"
    add("build", gradle .. " build")
    add("test", gradle .. " test")
  end
  if has["Package.swift"] then
    add("build", "swift build")
    add("test", "swift test")
  end
  if has["composer.json"] then
    add("install", "composer install")
    for _, t in ipairs { "test", "lint", "analyse", "format" } do
      if (facts.composer_scripts or {})[t] then
        add(t == "analyse" and "lint" or t, "composer " .. t)
      end
    end
    if declares "pestphp/pest" then
      add("test", "vendor/bin/pest")
    elseif declares "phpunit/phpunit" then
      add("test", "vendor/bin/phpunit")
    end
    if declares "phpstan" then
      add("lint", "vendor/bin/phpstan analyse")
    end
  end
  if has.Gemfile then
    add("install", "bundle install")
    if declares "rspec" then
      add("test", "bundle exec rspec")
    elseif has.Rakefile then
      add("test", "bundle exec rake test")
    end
    if declares "rubocop" then
      add("lint", "bundle exec rubocop")
    end
  end
  return out
end

--- Folders with how many files each, then the top files: as deep as fits in `max` rows (4 levels, else 3, else 2), so a
--- small project shows its feature folders (`lib/features/trips/data/`) and a big one still fits (what "Layout" is written from)
---@param files string[]
---@param max integer? rows (default 160)
---@param levels integer? deepest level to try (default 4)
---@return string[]
function M.tree(files, max, levels)
  max = max or 160
  local top = {}
  for _, f in ipairs(files) do
    if not f:find("/", 1, true) then
      top[#top + 1] = f
    end
  end
  table.sort(top)
  local out
  for depth = levels or 4, 1, -1 do
    local dirs = {}
    for _, f in ipairs(files) do
      local parts = vim.split(f, "/", { plain = true })
      for i = 1, math.min(depth, #parts - 1) do
        local key = table.concat(parts, "/", 1, i)
        dirs[key] = (dirs[key] or 0) + 1
      end
    end
    local names = vim.tbl_keys(dirs)
    table.sort(names)
    out = {}
    for _, name in ipairs(names) do
      local level = select(2, name:gsub("/", ""))
      out[#out + 1] = ("%s%s/ (%d)"):format(string.rep("  ", level), name:match "[^/]+$", dirs[name])
    end
    if #out + #top <= max or depth == 1 then
      break
    end
  end
  vim.list_extend(out, top)
  if #out > max then
    out = vim.list_slice(out, 1, max)
    out[#out + 1] = "…"
  end
  return out
end

---@param path string
---@param max integer lines
---@return string?
local function head(path, max)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
    if #lines >= max then
      lines[#lines + 1] = "…"
      break
    end
  end
  f:close()
  return table.concat(lines, "\n")
end

---@param root string
---@return string[]
local function list_files(root)
  local res = vim
    .system({ "git", "ls-files", "--cached", "--others", "--exclude-standard" }, { cwd = root, text = true })
    :wait()
  if res.code == 0 and res.stdout ~= "" then
    return vim.tbl_filter(function(f)
      return f ~= ""
    end, vim.split(res.stdout, "\n", { plain = true }))
  end
  local out = {}
  for name, kind in
    vim.fs.dir(root, {
      depth = 4,
      skip = function(dir)
        return not SKIP[vim.fs.basename(dir)]
      end,
    })
  do
    if kind == "file" then
      out[#out + 1] = name
    end
    if #out >= 3000 then
      break
    end
  end
  return out
end

--- The project's own name, from its manifest (package.json, pubspec, Cargo, pyproject, go.mod's last segment), else `fallback`
---@param manifests table<string, string>
---@param fallback string
---@return string
function M.project_name(manifests, fallback)
  local m = manifests
  local name = (m["package.json"] and m["package.json"]:match '"name"%s*:%s*"([^"]+)"')
    or (m["pubspec.yaml"] and m["pubspec.yaml"]:match "^name:%s*([%w_]+)")
    or (m["Cargo.toml"] and m["Cargo.toml"]:match '%[package%][^%[]-\nname%s*=%s*"([^"]+)"')
    or (m["pyproject.toml"] and (m["pyproject.toml"]:match '%[project%][^%[]-\nname%s*=%s*"([^"]+)"' or m["pyproject.toml"]:match '%[tool%.poetry%][^%[]-\nname%s*=%s*"([^"]+)"'))
    or (m["go.mod"] and m["go.mod"]:match "^module%s+%S-([^/%s]+)%s")
  return name or fallback
end

--- Where the documents go: the repository's root, else the current file's folder
---@param dir string?
---@return string
function M.root(dir)
  dir = dir or require("utils.project").file_dir()
  if dir == "" or vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.getcwd()
  end
  return vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return KitFacts
function M.collect(root)
  local files = list_files(root)
  local has = set(files)
  local manifests = {}
  for _, name in ipairs(M.MANIFESTS) do
    if has[name] then
      manifests[name] = head(root .. "/" .. name, (name == "package.json" or name == "pyproject.toml") and 120 or 60)
    end
  end
  --- the "scripts"/"tasks" table of a JSON manifest
  local function json_table(name, key)
    if not has[name] then
      return {}
    end
    local ok, json = pcall(vim.json.decode, require("utils.project").read(root .. "/" .. name) or "")
    return ok and type(json) == "table" and type(json[key]) == "table" and json[key] or {}
  end
  local scripts = json_table("package.json", "scripts")
  local targets = has.Makefile and M.make_targets(require("utils.project").read(root .. "/Makefile") or "") or {}
  local readme
  for _, name in ipairs { "README.md", "readme.md", "README" } do
    if has[name] then
      readme = head(root .. "/" .. name, 80)
      break
    end
  end
  local docs = {}
  for _, d in ipairs(require("agent.kit.compose").DOCS) do
    local text = require("utils.project").read(root .. "/" .. d.file)
    if text then
      docs[d.file] = text
    end
  end
  local facts = {
    root = root,
    name = M.project_name(manifests, vim.fs.basename(root)),
    files = files,
    languages = M.languages(files),
    manifests = manifests,
    scripts = scripts,
    targets = targets,
    readme = readme,
    docs = docs,
    deno_tasks = json_table("deno.json", "tasks"),
    composer_scripts = json_table("composer.json", "scripts"),
  }
  facts.commands = M.commands(facts)
  return facts
end

return M
