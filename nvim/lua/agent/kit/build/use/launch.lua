-- ── Build with agent · use: what kind of app this is and how to start it ────
-- From the manifest and the code (never from the model's text): a terminal UI (Bubble Tea, Ratatui, Textual, Ink…), a
-- command line program, a web app (a dev server, a static page, or a server the project itself runs), an Electron app,
-- or an Android app (Gradle or Flutter). Says how to build it and the command that starts it. Reads files only.
local M = {}

local read = function(path)
  return require("utils.project").read(path)
end

local TUI_DEPS = {
  go = { "charmbracelet/bubbletea", "rivo/tview", "gdamore/tcell", "jroimartin/gocui", "gizak/termui" },
  rust = { "ratatui", "cursive", "termion", "tui" },
  python = { "textual", "urwid", "prompt_toolkit", "npyscreen", "asciimatics" },
  node = { "ink", "blessed", "neo-blessed", "terminal-kit" },
}
local WEB_DEPS = {
  "vite",
  "next",
  "react-dom",
  "vue",
  "svelte",
  "@sveltejs/kit",
  "astro",
  "solid-js",
  "preact",
  "lit",
  "nuxt",
  "@remix-run/react",
  "webpack",
  "parcel",
  "express",
  "hono",
  "elysia",
  "fastify",
  "koa",
}
local SERVER_CODE = {
  go = { "ListenAndServe", "http%.Server{", '%.Run%(":', "fiber%.New", "echo%.New", "gin%.Default" },
  rust = { "axum::", "actix_web", "rocket::", "warp::", "TcpListener::bind" },
  python = { "FastAPI%(", "Flask%(", "uvicorn%.run", "django", "aiohttp%.web", "app%.run%(" },
}

---@param root string
---@param pattern fun(name: string, dir: string): boolean
---@param limit integer?
---@return string[] relative paths
local function find(root, pattern, limit)
  local found = vim.fs.find(function(name, dir)
    if dir:find("/node_modules", 1, true) or dir:find("/.git", 1, true) or dir:find("/target", 1, true) then
      return false
    end
    if dir:find("/build/", 1, true) or dir:find("/dist", 1, true) or dir:find("/.venv", 1, true) then
      return false
    end
    return pattern(name, dir)
  end, { path = root, type = "file", limit = limit or 200 })
  return vim.tbl_map(function(p)
    return p:sub(#root + 2)
  end, found)
end

---@param text string
---@param list string[]
---@param plain boolean?
---@return boolean
local function any(text, list, plain)
  for _, w in ipairs(list) do
    if text:find(w, 1, plain) then
      return true
    end
  end
  return false
end

--- The source of the files of one language (capped), to look for a server or a terminal UI library
---@param root string
---@param ext string
---@return string
local function sources(root, ext)
  local out, size = {}, 0
  for _, p in
    ipairs(find(root, function(name)
      return name:match("%." .. ext .. "$") ~= nil
    end, 120))
  do
    local text = read(root .. "/" .. p) or ""
    if size + #text > 400000 then
      break
    end
    size = size + #text
    out[#out + 1] = text
  end
  return table.concat(out, "\n")
end

---@class UseLaunch
---@field kind "tui"|"cli"|"web"|"electron"|"android"
---@field build string[]?  run once before the app starts (compiles it)
---@field argv string[]?   starts the app (web: the server; android: nil, the APK is installed)
---@field env table<string, string>?
---@field url string?      web: where to look first (else the server prints it, else the port)
---@field port integer?    web: the port the server is asked to use (PORT)
---@field static string?   web: a folder served as is
---@field apk string?      android: the APK the build writes (a glob)
---@field package string?  android: the application id
---@field what string      how it was recognized, for the feed

--- A free TCP port on 127.0.0.1
---@return integer
function M.free_port()
  local tcp = vim.uv.new_tcp()
  tcp:bind("127.0.0.1", 0)
  local port = tcp:getsockname().port
  tcp:close()
  return port
end

---@param root string
---@param bin string where a compiled binary goes
---@return UseLaunch?
local function go(root, bin)
  local gomod = read(root .. "/go.mod")
  if not gomod then
    return nil
  end
  local mains = find(root, function(name, dir)
    if not name:match "%.go$" or name:match "_test%.go$" then
      return false
    end
    local text = read(dir .. "/" .. name) or ""
    return text:match "^%s*package main%f[%s]" ~= nil or text:match "\npackage main%f[%s]" ~= nil
  end, 40)
  local dirs, seen = {}, {}
  for _, p in ipairs(mains) do
    local d = vim.fs.dirname(p)
    if not seen[d] then
      seen[d] = true
      dirs[#dirs + 1] = d
    end
  end
  if #dirs == 0 then
    return nil
  end
  table.sort(dirs, function(a, b) -- cmd/<name> first, the root next, examples and tools last
    local function rank(d)
      return (d:match "^cmd/" and 0) or (d == "." and 1) or ((d:match "example" or d:match "tool") and 3) or 2
    end
    return rank(a) == rank(b) and a < b or rank(a) < rank(b)
  end)
  local pkg = dirs[1] == "." and "." or ("./" .. dirs[1])
  local code = sources(root, "go")
  local kind = (any(gomod, TUI_DEPS.go, true) and "tui") or (any(code, SERVER_CODE.go) and "web") or "cli"
  return {
    kind = kind,
    build = { "go", "build", "-o", bin, pkg },
    argv = { bin },
    what = ("Go %s · %s"):format(kind, pkg),
  }
end

---@param root string
---@return UseLaunch?
local function rust(root)
  local cargo = read(root .. "/Cargo.toml")
  if not cargo then
    return nil
  end
  local name = cargo:match '%[%[bin%]%][^%[]-name%s*=%s*"([^"]+)"'
    or cargo:match '%[package%][^%[]-name%s*=%s*"([^"]+)"'
  if not name then
    return nil
  end
  local deps = cargo:match "%[dependencies%](.-)\n%[" or cargo:match "%[dependencies%](.*)$" or ""
  local kind = "cli"
  for _, d in ipairs(TUI_DEPS.rust) do
    if deps:find("\n" .. d .. "%s*=") then
      kind = "tui"
    end
  end
  if kind == "cli" and any(sources(root, "rs"), SERVER_CODE.rust) then
    kind = "web"
  end
  return {
    kind = kind,
    build = { "cargo", "build", "--quiet" },
    argv = { root .. "/target/debug/" .. name },
    what = ("Rust %s · %s"):format(kind, name),
  }
end

---@param root string
---@return UseLaunch?
local function python(root)
  local py = read(root .. "/pyproject.toml")
  local reqs = read(root .. "/requirements.txt") or ""
  if not py and reqs == "" and not vim.uv.fs_stat(root .. "/main.py") then
    return nil
  end
  local manifest = (py or "") .. "\n" .. reqs
  local uv = vim.fn.executable "uv" == 1 and py ~= nil
  local runner = uv and { "uv", "run" } or {}
  local script = (py or ""):match "%[project%.scripts%]%s*\n%s*([%w_%-]+)%s*="
  local argv
  if script then
    argv = vim.list_extend(vim.deepcopy(runner), { script })
    if not uv then
      argv = { script }
    end
  else
    for _, entry in ipairs { "main.py", "app.py", "cli.py", "__main__.py" } do
      if vim.uv.fs_stat(root .. "/" .. entry) then
        argv = vim.list_extend(vim.deepcopy(runner), { "python", entry })
        if not uv then
          argv = { "python3", entry }
        end
        break
      end
    end
    if not argv then
      local mainmod = find(root, function(name)
        return name == "__main__.py"
      end, 5)[1]
      local pkg = mainmod and vim.fs.dirname(mainmod):gsub("^src/", ""):gsub("/", ".")
      if pkg and pkg ~= "." then
        argv = vim.list_extend(vim.deepcopy(runner), { "python", "-m", pkg })
        if not uv then
          argv = { "python3", "-m", pkg }
        end
      end
    end
  end
  if not argv then
    return nil
  end
  local kind = "cli"
  for _, d in ipairs(TUI_DEPS.python) do
    if manifest:find("%f[%w_%-]" .. d:gsub("%p", "%%%0") .. "%f[^%w_%-]") then
      kind = "tui"
    end
  end
  if kind == "cli" and any(sources(root, "py"), SERVER_CODE.python) then
    kind = "web"
  end
  return {
    kind = kind,
    build = uv and { "uv", "sync", "--quiet" } or nil,
    argv = argv,
    what = ("Python %s · %s"):format(kind, table.concat(argv, " ")),
  }
end

---@param root string
---@param pm string
---@return UseLaunch?
local function node(root, pm)
  local text = read(root .. "/package.json")
  local ok, json = pcall(vim.json.decode, text or "")
  if not ok or type(json) ~= "table" then
    return nil
  end
  local deps = {}
  for _, key in ipairs { "dependencies", "devDependencies" } do
    for name in pairs(type(json[key]) == "table" and json[key] or {}) do
      deps[name] = true
    end
  end
  local scripts = type(json.scripts) == "table" and json.scripts or {}
  if deps.electron then
    return { kind = "electron", build = scripts.build and { pm, "run", "build" } or nil, what = "Electron app" }
  end
  for _, d in ipairs(TUI_DEPS.node) do
    if deps[d] then
      local bin = type(json.bin) == "string" and json.bin or (type(json.bin) == "table" and select(2, next(json.bin)))
      local argv = bin and { "node", root .. "/" .. bin } or (scripts.start and { pm, "run", "--silent", "start" })
      if argv then
        return {
          kind = "tui",
          build = scripts.build and { pm, "run", "build" } or nil,
          argv = argv,
          what = "Node terminal UI (" .. d .. ")",
        }
      end
    end
  end
  local web = false
  for _, d in ipairs(WEB_DEPS) do
    web = web or deps[d] == true
  end
  if web or vim.uv.fs_stat(root .. "/index.html") then
    local script = (scripts.dev and "dev") or (scripts.start and "start") or (scripts.preview and "preview")
    if script then
      return { kind = "web", argv = { pm, "run", script }, what = ("web app · %s run %s"):format(pm, script) }
    end
  end
  local bin = type(json.bin) == "string" and json.bin or (type(json.bin) == "table" and select(2, next(json.bin)))
  if bin then
    return {
      kind = "cli",
      build = scripts.build and { pm, "run", "build" } or nil,
      argv = { "node", root .. "/" .. bin },
      what = "Node command line · " .. bin,
    }
  end
  if scripts.start then
    return {
      kind = "cli",
      argv = { pm, "run", "--silent", "start" },
      what = ("Node program · %s run start"):format(pm),
    }
  end
end

---@param root string
---@return UseLaunch?
local function android(root)
  local gradle = (vim.uv.fs_stat(root .. "/app/build.gradle") and "app/build.gradle")
    or (vim.uv.fs_stat(root .. "/app/build.gradle.kts") and "app/build.gradle.kts")
    or (vim.uv.fs_stat(root .. "/android/app/build.gradle") and "android/app/build.gradle")
    or (vim.uv.fs_stat(root .. "/android/app/build.gradle.kts") and "android/app/build.gradle.kts")
  if not gradle then
    return nil
  end
  local text = read(root .. "/" .. gradle) or ""
  local id = text:match "applicationId%s*=?%s*[\"']([%w_%.]+)[\"']"
  if not id then
    local manifest = read(root .. "/" .. vim.fs.dirname(gradle) .. "/src/main/AndroidManifest.xml") or ""
    id = manifest:match 'package%s*=%s*"([%w_%.]+)"'
  end
  local flutter = vim.uv.fs_stat(root .. "/pubspec.yaml") ~= nil
  local build = flutter and { "flutter", "build", "apk", "--debug" }
    or { vim.uv.fs_stat(root .. "/gradlew") and "./gradlew" or "gradle", "assembleDebug", "--quiet" }
  return {
    kind = "android",
    build = build,
    apk = flutter and "build/app/outputs/flutter-apk/app-debug.apk"
      or (vim.fs.dirname(gradle) .. "/build/outputs/apk/debug/*.apk"),
    package = id,
    what = (flutter and "Flutter Android app · " or "Android app · ") .. (id or "?"),
  }
end

--- How the app at `root` is started, or nil and why not. `stack`: STACK.md (its words break a tie: a Flutter project
--- that says "web" is driven in the browser). `bin`: where a compiled binary goes.
---@param root string
---@param stack string?
---@param bin string
---@param pm string? the package manager (Node)
---@return UseLaunch?, string?
function M.detect(root, stack, bin, pm)
  stack = (stack or ""):lower()
  local wants_web = stack:find "%f[%w]web%f[^%w]" ~= nil or stack:find "browser" ~= nil
  local wants_mobile = stack:find "android" ~= nil or stack:find "mobile" ~= nil
  local a = android(root)
  if a and (wants_mobile or not wants_web) then
    return a
  end
  if vim.uv.fs_stat(root .. "/pubspec.yaml") and vim.uv.fs_stat(root .. "/web/index.html") and wants_web then
    return {
      kind = "web",
      build = { "flutter", "build", "web" },
      static = root .. "/build/web",
      what = "Flutter web app",
    }
  end
  local found = go(root, bin) or rust(root) or node(root, pm or "npm") or python(root)
  if found then
    return found
  end
  if vim.uv.fs_stat(root .. "/index.html") then
    return { kind = "web", static = root, what = "static page · index.html" }
  end
  if vim.uv.fs_stat(root .. "/pubspec.yaml") and vim.uv.fs_stat(root .. "/bin") then
    return { kind = "cli", argv = { "dart", "run" }, what = "Dart command line" }
  end
  return nil, "no entry point the build can start (a main package, a bin, a dev script, an index.html, an Android app)"
end

return M
