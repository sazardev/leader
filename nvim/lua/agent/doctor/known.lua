-- Known problems of a failing build / run: the free first answer of the troubleshooting agent. PURE (no IO, no
-- model, no vim API): given the text the tool printed it recognizes well-known failures and returns what they mean
-- and the concrete way out. A match is shown to the user before any model is asked.
--
-- Contract:
--   M.find(text, ctx) -> DoctorFinding[]   (deduplicated by id, at most 6, most specific first)
--   M.ids()           -> string[]          (every id of the table, in order)
--
--   ctx = { has = fun(relpath): boolean   does that file or folder exist in the project root
--           pm  = "pnpm"|"npm"|"yarn"|"bun"|nil   the project's package manager (default npm)
--           root = string? }
--
-- DoctorFinding = { id, title, cause, evidence (the matched line, trimmed, <= 200 chars), steps, confidence }
-- DoctorStep    = { kind = "command"|"manual", title, run? (command only), note? }
--
-- How the table works: ENTRIES is ordered from the most specific signature to the most generic one (an entry earlier
-- in the table wins and ends up first in the result). Each entry has `patterns` (Lua patterns matched
-- case-insensitively on the original text, so captures keep their case; or a function(text, lower) -> pos, captures)
-- and `build(captures, ctx, m)`, which returns the finding (without id/evidence) or nil to skip. Every string pattern
-- is guarded by a plain-text prefilter (its longest literal run) so a big log that does not carry the signature costs
-- one memchr-like scan per pattern. Patterns are bounded by lines (`[^\n]`) and never nest quantifiers.

local M = {}

local MAX = 6

---------------------------------------------------------------------------------------------------------------------
-- Pattern machinery
---------------------------------------------------------------------------------------------------------------------

local MAGIC = {
  ["^"] = 1,
  ["$"] = 1,
  ["("] = 1,
  [")"] = 1,
  ["%"] = 1,
  ["."] = 1,
  ["["] = 1,
  ["]"] = 1,
  ["*"] = 1,
  ["+"] = 1,
  ["-"] = 1,
  ["?"] = 1,
}

--- Skips a `[...]` set that starts at `i`; returns the index of its closing bracket.
local function set_end(p, i)
  local n, j = #p, i + 1
  if p:sub(j, j) == "^" then
    j = j + 1
  end
  if p:sub(j, j) == "]" then
    j = j + 1
  end
  while j <= n and p:sub(j, j) ~= "]" do
    if p:sub(j, j) == "%" then
      j = j + 1
    end
    j = j + 1
  end
  return j
end

--- Case-insensitive version of a Lua pattern: bare letters become `[xX]`; escapes and sets are copied as written.
local function ci(p)
  local out, i, n = {}, 1, #p
  while i <= n do
    local c = p:sub(i, i)
    if c == "%" then
      out[#out + 1] = p:sub(i, i + 1)
      i = i + 2
    elseif c == "[" then
      local j = set_end(p, i)
      out[#out + 1] = p:sub(i, j)
      i = j + 1
    elseif c:match("%a") then
      out[#out + 1] = "[" .. c:lower() .. c:upper() .. "]"
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Longest run of literal characters of a pattern (lowercase), used as a plain-text prefilter; nil if shorter than 3.
local function literal(p)
  local best, cur, i, n = "", "", 1, #p
  local function flush()
    if #cur > #best then
      best = cur
    end
    cur = ""
  end
  while i <= n do
    local c = p:sub(i, i)
    if c == "%" then
      flush()
      i = i + 2
    elseif c == "[" then
      flush()
      i = set_end(p, i) + 1
    elseif c == "*" or c == "?" or c == "-" then
      cur = cur:sub(1, -2)
      flush()
      i = i + 1
    elseif MAGIC[c] then
      flush()
      i = i + 1
    else
      cur = cur .. c:lower()
      i = i + 1
    end
  end
  flush()
  return #best >= 3 and best or nil
end

--- Start and end of the line that holds `pos`, and its text (capped, not trimmed).
local function line_bounds(text, pos)
  local ls = pos
  local lim = math.max(1, pos - 2000)
  while ls > lim and text:byte(ls - 1) ~= 10 do
    ls = ls - 1
  end
  local le = (text:find("\n", pos, true) or (#text + 1)) - 1
  return ls, le, text:sub(ls, math.min(le, ls + 1999))
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- The matched line, trimmed to 200 chars (a window around the match if the line is huge).
local function evidence_of(text, pos)
  local ls, le = line_bounds(text, pos)
  local from = ls
  if le - ls + 1 > 200 then
    from = math.max(ls, pos - 60)
  end
  return trim(text:sub(from, math.min(le, from + 399))):sub(1, 200)
end

local function shell_quote(s)
  if s:match("^[%w_@%%+=:,./~-]+$") then
    return s
  end
  return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

local function cmd(title, run, note)
  return { kind = "command", title = title, run = run, note = note }
end

local function man(title, note)
  return { kind = "manual", title = title, note = note }
end

---------------------------------------------------------------------------------------------------------------------
-- Shared helpers for the builders
---------------------------------------------------------------------------------------------------------------------

local PMS = {
  npm = { install = "npm install", add = "npm install", add_dev = "npm install -D", exec = "npx", run = "npm run" },
  pnpm = { install = "pnpm install", add = "pnpm add", add_dev = "pnpm add -D", exec = "pnpm exec", run = "pnpm run" },
  yarn = { install = "yarn", add = "yarn add", add_dev = "yarn add -D", exec = "yarn", run = "yarn" },
  bun = { install = "bun install", add = "bun add", add_dev = "bun add -d", exec = "bunx", run = "bun run" },
}

local function pm_of(ctx)
  return PMS[ctx.pm or "npm"] or PMS.npm
end

--- The npm package behind an import specifier ("lodash/fp" -> "lodash", "@a/b/c" -> "@a/b").
local function pkg_root(name)
  return name:match("^(@[^/]+/[^/]+)") or name:match("^([^/]+)") or name
end

local function is_path_like(name)
  return name:find("^[%./~]") ~= nil or name:find("^file:") ~= nil
end

local COMPOSE_FILES = { "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml" }

local function has_compose(ctx)
  for _, f in ipairs(COMPOSE_FILES) do
    if ctx.has(f) then
      return true
    end
  end
  return false
end

--- Last `File "x", line N` of a Python traceback before `pos`.
local function py_frame(text, pos)
  local seg = text:sub(math.max(1, pos - 1500), pos)
  local file, line
  for f, l in seg:gmatch('File "([^"]+)", line (%d+)') do
    file, line = f, l
  end
  return file, line
end

--- First project frame (`path.go:N`) after `pos` in a Go panic trace, skipping the runtime and the standard library.
local function go_frame(text, pos)
  local seg = text:sub(pos, pos + 4000)
  for frame in seg:gmatch("\n%s*([^\n%s]+%.go:%d+)") do
    if
      not (
        frame:find("/usr/local/go/", 1, true)
        or frame:find("/usr/lib/go", 1, true)
        or frame:find("/runtime/", 1, true)
        or frame:find("/go/pkg/mod/", 1, true)
        or frame:find("^runtime")
      )
    then
      return frame
    end
  end
  return nil
end

local PORT_SERVICES = {
  [5432] = { name = "PostgreSQL", svc = "postgres", unit = "postgresql" },
  [3306] = { name = "MySQL", svc = "mysql", unit = "mysql" },
  [6379] = { name = "Redis", svc = "redis", unit = "redis-server" },
  [27017] = { name = "MongoDB", svc = "mongo", unit = "mongod" },
  [9200] = { name = "Elasticsearch", svc = "elasticsearch", unit = "elasticsearch" },
  [5672] = { name = "RabbitMQ", svc = "rabbitmq", unit = "rabbitmq-server" },
  [9092] = { name = "Kafka", svc = "kafka", unit = "kafka" },
  [11211] = { name = "Memcached", svc = "memcached", unit = "memcached" },
}

--- Command names that apt can install, and the package.
local APT = {
  make = "build-essential",
  gcc = "build-essential",
  ["g++"] = "build-essential",
  cc = "build-essential",
  git = "git",
  curl = "curl",
  wget = "wget",
  jq = "jq",
  unzip = "unzip",
  zip = "zip",
  cmake = "cmake",
  ["pkg-config"] = "pkg-config",
  rsync = "rsync",
  go = "golang-go",
  java = "default-jdk",
  javac = "default-jdk",
  sqlite3 = "sqlite3",
  psql = "postgresql-client",
  ["redis-cli"] = "redis-tools",
  mysql = "mysql-client",
  gdb = "gdb",
  clang = "clang",
  protoc = "protobuf-compiler",
  ffmpeg = "ffmpeg",
}

local PIP_NAMES = {
  cv2 = "opencv-python",
  PIL = "pillow",
  yaml = "pyyaml",
  sklearn = "scikit-learn",
  bs4 = "beautifulsoup4",
  dotenv = "python-dotenv",
  jwt = "pyjwt",
  dateutil = "python-dateutil",
  attr = "attrs",
  MySQLdb = "mysqlclient",
  serial = "pyserial",
  git = "GitPython",
  Crypto = "pycryptodome",
  magic = "python-magic",
}

local VENV_ACTIVATE = ". .venv/bin/activate"

---------------------------------------------------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------------------------------------------------

local ENTRIES = {}

local function E(id, patterns, build)
  ENTRIES[#ENTRIES + 1] = { id = id, patterns = patterns, build = build }
end

-- ===== Node / JS / TS ====================================================================================

E("ts-module-not-found", {
  "ts2307: cannot find module ['\"]([^'\"]+)['\"]",
  "ts2792: cannot find module ['\"]([^'\"]+)['\"]",
}, function(c, ctx)
  local mod, pm = c[1], pm_of(ctx)
  local f = {
    title = "TypeScript cannot resolve '" .. mod .. "'",
    cause = "The compiler found no file or package for that import.",
    confidence = "high",
  }
  if mod:find("^%.") then
    f.cause = "The relative file does not exist at that path, has another name or letter case, or is generated and not built yet."
    f.steps = {
      man("Check the path and its letter case", "Linux is case-sensitive; '" .. mod .. "' must match the file name exactly."),
      man("Run the codegen or build that creates it", "Only if the file is generated."),
    }
  elseif mod:find("^[@~#]/") or mod:find("^[~#]") then
    f.cause = "'" .. mod .. "' looks like a path alias; the compiler does not know it (or the bundler / test runner does not)."
    f.steps = {
      man("Check the alias in tsconfig.json", "compilerOptions.paths (and baseUrl) must map it."),
      man("Teach the bundler or test runner the same alias", "vite resolve.alias, jest moduleNameMapper, tsconfig-paths."),
    }
  else
    local root = pkg_root(mod)
    if ctx.has("node_modules/" .. root) then
      f.cause = "'" .. root .. "' is installed but ships no type declarations."
      local types = "@types/" .. root:gsub("^@", ""):gsub("/", "__")
      f.steps = {
        cmd("Install its type declarations", pm.add_dev .. " " .. shell_quote(types), "If no @types package exists, add a `declare module '" .. root .. "'` in a .d.ts file."),
      }
    elseif ctx.has("node_modules") then
      f.cause = "The package '" .. root .. "' is not installed."
      f.steps = {
        cmd("Install the package", pm.add .. " " .. shell_quote(root)),
        cmd("Reinstall everything if it is already in package.json", pm.install),
      }
    else
      f.cause = "node_modules does not exist: the dependencies were never installed."
      f.steps = { cmd("Install the dependencies", pm.install, "Installs everything package.json lists, including '" .. root .. "'.") }
    end
  end
  return f
end)

E("node-module-missing", {
  "cannot find module '([^']+)'",
  'cannot find module "([^"]+)"',
  "cannot find package '([^']+)' imported from",
  "failed to resolve import \"([^\"]+)\"",
  "module not found: [^\n]-can't resolve '([^']+)'",
}, function(c, ctx, m)
  local mod, pm = c[1], pm_of(ctx)
  if m.line:lower():find("or its corresponding type declarations", 1, true) then
    return nil
  end
  local f = {
    title = "A Node module is missing: " .. mod,
    cause = "Node or the bundler could not resolve '" .. mod .. "'.",
    confidence = "high",
  }
  if mod:find("^node:") then
    f.cause = "'" .. mod .. "' is a Node built-in; the runtime is too old or the bundler targets the browser."
    f.steps = { man("Check the Node version and the build target", "Run `node --version` and compare with the engines field.") }
  elseif is_path_like(mod) then
    f.title = "Node cannot find the file " .. mod
    f.cause = "The file does not exist: wrong path, wrong letter case, or build output that was not produced yet."
    f.steps = {
      man("Build the project if the path is an output file", "Output folders like dist/ only exist after the build."),
      man("Check the path and its letter case"),
    }
  elseif not ctx.has("node_modules") then
    f.cause = "node_modules does not exist: the dependencies were never installed."
    f.steps = { cmd("Install the dependencies", pm.install, "Installs everything package.json lists, including '" .. pkg_root(mod) .. "'.") }
  else
    local root = pkg_root(mod)
    f.steps = {
      cmd("Install the missing package", pm.add .. " " .. shell_quote(root), "If it is already in package.json, a plain install is enough."),
      cmd("Reinstall all dependencies", pm.install),
    }
  end
  return f
end)

E("node-esm-cjs", {
  "cannot use import statement outside a module",
  "err_require_esm",
  "require is not defined in es module scope",
  "must use import to load es module",
  "unexpected token 'export'",
}, function()
  return {
    title = "Node mixes ES modules and CommonJS",
    cause = "A file uses import/export while Node treats it as CommonJS (or require() loads an ES module).",
    steps = {
      man("Pick one module system", 'Add "type": "module" to package.json, or rename the file to .mjs / .cjs.'),
      man("For TypeScript check tsconfig.json", "module and moduleResolution must match how the code runs (NodeNext, ESNext...)."),
    },
    confidence = "medium",
  }
end)

E("node-port-in-use", {
  "eaddrinuse[^\n]*:(%d+)",
}, function(c)
  local port = c[1]
  return {
    title = "Port " .. port .. " is already in use",
    cause = "Another process (often a previous run of this server) is still listening on port " .. port .. ".",
    steps = {
      cmd("Find the process holding the port", "lsof -i :" .. port, "The PID column is the process to stop."),
      cmd("Same, with ss", "ss -ltnp 'sport = :" .. port .. "'", "Use this if lsof is not installed."),
      man("Stop that process or use another port", "For example PORT=" .. (tonumber(port) + 1) .. " when the app reads PORT."),
    },
    confidence = "high",
  }
end)

E("npm-eresolve", {
  "eresolve",
}, function(_, _, m)
  local peer, from = m.text:match("[Pp]eer ([^\n]+) from ([^\n]+)", m.s)
  local cause = "Two packages ask for incompatible versions of the same dependency (usually a peer dependency)."
  if peer and from then
    cause = trim(from):sub(1, 80) .. " wants " .. trim(peer):sub(1, 80) .. ", which conflicts with what is installed."
  end
  return {
    title = "npm cannot resolve the dependency tree",
    cause = cause,
    steps = {
      man("Align the versions", "Upgrade or downgrade the package named in the message so the ranges overlap."),
      cmd("Install ignoring peer conflicts", "npm install --legacy-peer-deps", "Works like npm 6 did; fine for most apps, hides real incompatibilities."),
    },
    confidence = "high",
  }
end)

E("node-engine-mismatch", {
  "unsupported engine",
  'the engine "node" is incompatible',
  "requires node%.js",
  "you are using node%.js",
}, function(_, ctx, m)
  local t = m.text
  local want = t:match('[Rr]equired: {[^}]-"node":%s*"([^"]+)"')
    or t:match('[Ee]xpected version "([^"]+)"')
    or t:match("[Rr]equires [Nn]ode%.js ([^%s,;]+)")
  local steps = {}
  if ctx.has(".nvmrc") then
    steps[#steps + 1] = cmd("Switch to the project's Node", "nvm use", "Reads .nvmrc; nvm is a shell function, run it in your own terminal.")
  elseif ctx.has(".node-version") then
    steps[#steps + 1] = cmd("Switch to the project's Node", "nvm use $(cat .node-version)", "nvm is a shell function, run it in your own terminal.")
  else
    steps[#steps + 1] = man("Install a Node that satisfies the engines field", "With nvm: `nvm install " .. (want and want:gsub("[^%d%.]", "") or "--lts") .. "`.")
  end
  steps[#steps + 1] = cmd("Check the active version", "node --version")
  return {
    title = "The Node version does not match the project" .. (want and (" (needs " .. want .. ")") or ""),
    cause = "package.json (engines) or a tool requires a different Node than the one running.",
    steps = steps,
    confidence = "high",
  }
end)

E("inotify-limit", {
  "system limit for number of file watchers reached",
  "user limit of inotify watches reached",
  "inotify_add_watch",
}, function()
  return {
    title = "The file watcher limit is reached",
    cause = "Linux limits how many files one user can watch (inotify); dev servers watching node_modules hit it.",
    steps = {
      cmd("See the current limit", "sysctl fs.inotify.max_user_watches", "Often 8192 on older systems."),
      man("Raise it permanently", "Put fs.inotify.max_user_watches=524288 in /etc/sysctl.d/99-inotify.conf (needs root), then run `sysctl --system`."),
      man("Or watch less", "Exclude node_modules, dist and .git from the watcher."),
    },
    confidence = "high",
  }
end)

E("npm-eacces", {
  "eacces: permission denied, %a+ '([^']+)'",
  "eacces: permission denied, %a+ ([^%s']+)",
  "code eacces",
}, function(c)
  local path = c[1]
  local global = path and (path:find("^/usr") or path:find("^/opt") or path:find("/lib/node_modules", 1, true))
  if global or not path then
    return {
      title = "npm cannot write to the global folder",
      cause = "Global packages go to a system folder your user cannot write to.",
      steps = {
        cmd("Use a folder in your home for global packages", "npm config set prefix ~/.npm-global", "Then add ~/.npm-global/bin to PATH."),
        man("Or use a Node version manager", "nvm / fnm keep Node and its global packages in your home; no sudo needed."),
      },
      confidence = "high",
    }
  end
  return {
    title = "npm cannot write to " .. path,
    cause = "The folder is owned by another user, usually root after an earlier run with sudo.",
    steps = {
      cmd("See who owns it", "ls -ld " .. shell_quote(path)),
      man("Give it back to your user", "`sudo chown -R $USER " .. shell_quote(path) .. "`, and never run npm with sudo."),
    },
    confidence = "high",
  }
end)

E("node-heap-oom", {
  "heap out of memory",
  "reached heap limit allocation failed",
}, function()
  return {
    title = "Node ran out of memory",
    cause = "The JavaScript heap hit its limit (default is a fraction of RAM), typical of big bundles and type checks.",
    steps = {
      cmd("See the current heap limit in MB", [[node -e "console.log(require('v8').getHeapStatistics().heap_size_limit/1048576)"]]),
      man("Re-run with more heap", "Prefix the failing command with NODE_OPTIONS=--max-old-space-size=4096 (value in MB)."),
      man("Find what eats the memory", "A huge bundle, a watcher on node_modules, or a leak in a loop."),
    },
    confidence = "high",
  }
end)

-- ===== Python ============================================================================================

E("py-module-missing", {
  "modulenotfounderror: no module named ['\"]([%w_%.]+)['\"]",
  "importerror: no module named ['\"]?([%w_%.]+)",
}, function(c, ctx)
  local mod = c[1]
  local root = mod:match("^[^%.]+") or mod
  local pip = PIP_NAMES[root] or root
  local f = {
    title = "A Python module is missing: " .. mod,
    cause = "The interpreter running the code has no package '" .. root .. "': the virtualenv is not active or the dependencies were not installed.",
    confidence = "high",
  }
  if ctx.has(root .. ".py") or ctx.has(root .. "/__init__.py") then
    f.cause = "'" .. root .. "' is a local module but it is not on the import path of this run."
    f.steps = {
      man("Run from the project root", "Or set PYTHONPATH=. so the project folder is importable."),
      cmd("Check the interpreter in use", "python3 -c 'import sys; print(sys.executable)'"),
    }
    f.confidence = "medium"
    return f
  end
  local venv = (ctx.has(".venv") and ".venv") or (ctx.has("venv") and "venv") or nil
  local deps
  if ctx.has("requirements.txt") then
    deps = "pip install -r requirements.txt"
  elseif ctx.has("pyproject.toml") then
    deps = "pip install -e ."
  else
    deps = "pip install " .. shell_quote(pip)
  end
  if venv then
    f.steps = {
      cmd("Install into the project's virtualenv", ". " .. venv .. "/bin/activate && " .. deps),
      man("Run with that virtualenv active", "Also select it as the interpreter in your editor."),
    }
  else
    f.steps = {
      cmd("Create a virtualenv and install", "python3 -m venv .venv && " .. VENV_ACTIVATE .. " && " .. deps),
      man("Run with that virtualenv active", "Also select it as the interpreter in your editor."),
    }
  end
  return f
end)

E("py-externally-managed", {
  "externally%-managed%-environment",
  "this environment is externally managed",
}, function(_, ctx)
  local deps = ctx.has("requirements.txt") and "pip install -r requirements.txt" or "pip install <package>"
  return {
    title = "pip refuses to install into the system Python",
    cause = "The distribution marks its Python as externally managed (PEP 668); packages must live in a virtualenv.",
    steps = {
      cmd("Create a virtualenv", "python3 -m venv .venv", "Then `" .. VENV_ACTIVATE .. " && " .. deps .. "`."),
      man("For a command-line tool use pipx", "`pipx install <tool>` isolates it. Avoid --break-system-packages."),
    },
    confidence = "high",
  }
end)

E("python-not-found", {
  "command not found: (python[%d%.]*)",
  "(python[%d%.]*): command not found",
  "(python[%d%.]*): not found",
  "command not found: (pip[%d%.]*)",
  "(pip[%d%.]*): command not found",
  "'(python[%d%.]*)' is not recognized as an internal or external command",
}, function(c)
  local name = c[1]
  local is_pip = name:lower():find("^pip") ~= nil
  local steps
  if is_pip then
    steps = {
      cmd("Use pip through Python", "python3 -m pip --version"),
      cmd("Install pip", "sudo apt install python3-pip", "Missing system package (Debian/Ubuntu); macOS: it comes with brew's python."),
    }
  else
    steps = {
      cmd("Check for python3", "python3 --version", "Most systems ship only `python3`; use it instead of `" .. name .. "`."),
      cmd("Install Python", "sudo apt install python3 python3-venv", "Missing system package (Debian/Ubuntu); macOS: brew install python."),
    }
  end
  return {
    title = "'" .. name .. "' is not installed or not on PATH",
    cause = "The shell cannot find that program; many systems only provide python3 / python3 -m pip.",
    steps = steps,
    confidence = "high",
  }
end)

E("py-indentation", {
  "indentationerror: ([^\n]+)",
  "taberror: ([^\n]+)",
}, function(c, _, m)
  local file, line = py_frame(m.text, m.s)
  local where = file and (file .. (line and (":" .. line) or "")) or nil
  local steps = {
    man("Fix the indentation" .. (where and (" at " .. where) or ""), "Use spaces only (4 per level); tabs and spaces cannot be mixed."),
  }
  if file and file:find("%.pyw?$") then
    steps[#steps + 1] = cmd("Find tabs in the file", "grep -nP '\\t' " .. shell_quote(file), "Any output is a line indented with a tab.")
  end
  return {
    title = "Python indentation is inconsistent" .. (where and (" (" .. where .. ")") or ""),
    cause = trim(c[1]):sub(1, 120) .. ".",
    steps = steps,
    confidence = "high",
  }
end)

E("py-syntax-error", {
  function(text, lower)
    local from = 1
    while true do
      local s = lower:find("syntaxerror:", from, true)
      if not s then
        return nil
      end
      if s == 1 or text:byte(s - 1) == 10 then
        local file, line = py_frame(text, s)
        if file and (file:find("%.pyw?$") or file:find("^<")) then
          local msg = trim(text:match("^[^\n]*", s + 12) or "")
          return s, { file, line, msg }
        end
      end
      from = s + 1
    end
  end,
}, function(c)
  return {
    title = "Python cannot parse " .. c[1] .. ":" .. c[2],
    cause = (c[3] ~= "" and (c[3]:sub(1, 100) .. ". ") or "") .. "Either the line is wrong, or it uses syntax newer than the Python running it.",
    steps = {
      man("Open " .. c[1] .. " at line " .. c[2], "The caret in the traceback points at the first token Python could not read."),
      cmd("Check the Python version", "python3 --version", "match, walrus, parenthesized with and f-string nesting need recent versions; compare with requires-python."),
    },
    confidence = "medium",
  }
end)

-- ===== Go ================================================================================================

E("go-missing-sum", {
  "missing go%.sum entry for module providing package ([^%s;]+)",
  "missing go%.sum entry",
}, function(c)
  return {
    title = "go.sum is missing a checksum" .. (c[1] and (" for " .. c[1]) or ""),
    cause = "A dependency is used but its hash is not recorded in go.sum.",
    steps = {
      cmd("Add the missing entries", "go mod tidy", "Also drops unused requirements; commit go.mod and go.sum."),
      cmd("Or download only what is missing", "go mod download"),
    },
    confidence = "high",
  }
end)

E("go-mod-tidy", {
  "updates to go%.mod needed",
  "no required module provides package ([^%s;:]+)",
  "cannot find module providing package ([^%s:]+)",
  'cannot find package "([^"]+)" in any of',
}, function(c)
  local pkg = c[1]
  local steps = {}
  if pkg and pkg:match("^[^/]+%.[^/]+/") then
    steps[#steps + 1] = cmd("Add the dependency", "go get " .. pkg, "Only if it is an external module; for your own packages check the import path.")
  end
  steps[#steps + 1] = cmd("Sync go.mod with the imports", "go mod tidy")
  return {
    title = pkg and ("Go has no module for " .. pkg) or "go.mod is out of date",
    cause = "The imports and go.mod disagree: a dependency is not required yet, or the import path is wrong.",
    steps = steps,
    confidence = "high",
  }
end)

E("go-cgo-compiler", {
  'cgo: c compiler "([^"]+)" not found',
  'exec: "(gcc)": executable file not found',
  'exec: "(cc)": executable file not found',
}, function(c)
  return {
    title = "Go needs a C compiler (" .. c[1] .. " is missing)",
    cause = "A dependency uses cgo (sqlite3, some net or image libraries) and there is no C compiler on PATH.",
    steps = {
      cmd("Install the C toolchain", "sudo apt install build-essential", "Missing system package (Debian/Ubuntu); macOS: xcode-select --install."),
      cmd("Or build without cgo", "CGO_ENABLED=0 go build ./...", "Only works when no dependency really needs C."),
    },
    confidence = "high",
  }
end)

E("go-build-constraints", {
  "build constraints exclude all go files in ([^\n]+)",
}, function(c)
  return {
    title = "Every Go file of " .. trim(c[1]) .. " is excluded by build constraints",
    cause = "File suffixes (_linux, _windows), //go:build lines or disabled cgo remove all files for this OS / arch.",
    steps = {
      cmd("See the target the build uses", "go env GOOS GOARCH CGO_ENABLED"),
      man("Check the //go:build lines", "Pass -tags if the files need a tag, or build for the right GOOS/GOARCH."),
    },
    confidence = "high",
  }
end)

E("go-not-in-std", {
  "package ([^%s]+) is not in std",
  "package ([^%s]+) is not in goroot",
}, function(c)
  local pkg = c[1]
  local steps = {}
  if pkg:match("^[^/]+%.[^/]+/") then
    steps[#steps + 1] = cmd("Add it as a dependency", "go get " .. pkg)
  end
  steps[#steps + 1] = cmd("Check the Go version", "go version", "Newer standard packages (slices, maps, log/slog, cmp) need Go 1.21+; compare with the go line of go.mod.")
  steps[#steps + 1] = man("Check the import spelling", "A path without a dot in its first segment is looked up in the standard library.")
  return {
    title = "Go does not know the package " .. pkg,
    cause = "The path is looked up in the standard library: it is a typo, a third-party path missing its host, or a std package newer than your Go.",
    steps = steps,
    confidence = "high",
  }
end)

E("go-unused", {
  '"([^"]+)" imported and not used',
  '"([^"]+)" imported but not used',
  "declared and not used: ([%w_]+)",
  "([%w_]+) declared and not used",
  "([%w_]+) declared but not used",
}, function(c, _, m)
  local what = m.pi <= 2 and ("import " .. c[1]) or ("variable " .. c[1])
  return {
    title = "Go refuses to compile the unused " .. what,
    cause = "Go treats unused imports and local variables as errors.",
    steps = {
      man("Fix it in the code", "Use it, delete it, or assign it to _. The agent's fix-from-output handles it."),
    },
    confidence = "high",
  }
end)

E("go-panic", {
  "panic: runtime error: ([^\n]+)",
}, function(c, _, m)
  local msg = trim(c[1])
  local frame = go_frame(m.text, m.s)
  local cause = "The program hit a runtime error: " .. msg .. "."
  local l = msg:lower()
  if l:find("nil pointer", 1, true) then
    cause = "A nil pointer is dereferenced: a value was used before it was set, or an error was ignored."
  elseif l:find("index out of range", 1, true) then
    cause = "A slice or array is indexed beyond its length."
  elseif l:find("nil map", 1, true) then
    cause = "A map is written to before it was created with make or a literal."
  end
  return {
    title = "Go panic: " .. msg:sub(1, 80),
    cause = cause,
    steps = {
      man(frame and ("Open " .. frame) or "Open the first frame of your own code in the trace", "Skip frames in runtime/ and the standard library; the first project frame is where it breaks."),
      cmd("Look for suspicious code", "go vet ./..."),
    },
    confidence = "high",
  }
end)

-- ===== Rust ==============================================================================================

E("rust-linker-missing", {
  "linker [`']?([%w_%-]+)[`']? not found",
}, function(c)
  return {
    title = "Rust cannot link: " .. c[1] .. " is missing",
    cause = "cargo needs a C linker (cc / gcc) and none is installed.",
    steps = {
      cmd("Install the C toolchain", "sudo apt install build-essential", "Missing system package (Debian/Ubuntu); Fedora: dnf groupinstall 'Development Tools'; macOS: xcode-select --install."),
      cmd("Check the linker", "cc --version"),
    },
    confidence = "high",
  }
end)

E("rust-openssl", {
  "failed to run custom build command for [`']openssl%-sys",
  "could not find directory of openssl installation",
  "could not find openssl via pkg%-config",
}, function()
  return {
    title = "openssl-sys cannot find OpenSSL",
    cause = "The openssl crate needs the OpenSSL development files and pkg-config on the system.",
    steps = {
      cmd("Install the system packages", "sudo apt install pkg-config libssl-dev", "Missing system packages (Debian/Ubuntu); Fedora: openssl-devel pkgconf; macOS: brew install openssl pkg-config."),
      cmd("Or build OpenSSL from source", "cargo add openssl --features vendored", "Needs perl and make; switching the dependency to rustls avoids OpenSSL altogether."),
    },
    confidence = "high",
  }
end)

E("rust-unresolved-import", {
  "error%[e0432%]: unresolved import [`']?([^\n]+)",
  "error%[e0433%]: failed to resolve: use of undeclared crate or module [`']([%w_]+)[`']",
}, function(c)
  local path = c[1]:gsub("[`']", ""):gsub("%s+$", "")
  local seg = path:match("^([%w_]+)")
  local steps = { man("Check the use path and the mod declarations", "A new file needs `mod name;` in its parent, and paths start with crate::, self:: or super::.") }
  if seg and not ({ crate = 1, self = 1, super = 1, std = 1, core = 1, alloc = 1 })[seg] and seg:match("^[a-z]") then
    steps[#steps + 1] = cmd("If it is an external crate, add it", "cargo add " .. seg:gsub("_", "-"), "Only when '" .. seg .. "' is not in Cargo.toml yet.")
  end
  return {
    title = "Rust cannot resolve the import " .. path:sub(1, 80),
    cause = "The path names a module or crate that is not declared, not exported (pub), or not a dependency.",
    steps = steps,
    confidence = "medium",
  }
end)

E("rust-no-matching-package", {
  "no matching package named [`']([^`']+)[`'] found",
}, function(c)
  return {
    title = "cargo finds no package named " .. c[1],
    cause = "The name is misspelled, lives in another registry, or is a path / git dependency written as a version.",
    steps = {
      cmd("Search the registry", "cargo search " .. shell_quote(c[1]) .. " --limit 5"),
      man("Check the dependency entry in Cargo.toml", "Registry, path and git dependencies are written differently."),
    },
    confidence = "high",
  }
end)

E("rust-toolchain-old", {
  "feature [`']edition(%d+)[`'] is required",
  "lock file version (%d+) was found, but this version of cargo does not support",
  "requires rustc ([%d%.]+) or newer",
}, function(c, _, m)
  local cause = "The project needs a newer Rust than the one installed."
  if m.pi == 1 then
    cause = "The project uses edition " .. c[1] .. ", which the installed cargo does not know."
  elseif m.pi == 2 then
    cause = "Cargo.lock was written by a newer cargo (lock file version " .. c[1] .. ")."
  else
    cause = "A dependency requires rustc " .. c[1] .. " or newer."
  end
  return {
    title = "The Rust toolchain is too old",
    cause = cause,
    steps = {
      cmd("Update the toolchain", "rustup update stable"),
      cmd("Check the version in use", "rustc --version"),
      man("Pin the toolchain if the project needs a specific one", "A rust-toolchain.toml at the root selects it per project."),
    },
    confidence = "high",
  }
end)

E("rust-panic", {
  "thread '([^']+)' panicked at ([^\n]+)",
}, function(c)
  local where = trim(c[2]):gsub(":$", "")
  return {
    title = "Rust panic at " .. where:sub(1, 80),
    cause = "The program panicked (unwrap on None/Err, index out of bounds, overflow, explicit panic!) in thread '" .. c[1] .. "'.",
    steps = {
      man("Open " .. where:sub(1, 80), "The message under the panic line says which check failed."),
      man("Re-run with a backtrace", "Prefix the command with RUST_BACKTRACE=1 and read the first frame in your crate."),
    },
    confidence = "high",
  }
end)

-- ===== Java / Kotlin / Gradle ============================================================================

E("java-home", {
  "java_home is not set",
  "java_home is set to an invalid directory: ([^\n]+)",
  "the java_home environment variable is not defined correctly",
}, function(c)
  return {
    title = c[1] and ("JAVA_HOME points to a missing folder: " .. trim(c[1]):sub(1, 80)) or "JAVA_HOME is not set",
    cause = "The build tool looks for a JDK through JAVA_HOME and cannot find one.",
    steps = {
      cmd("List the installed JDKs", "ls /usr/lib/jvm", "macOS: /usr/libexec/java_home -V."),
      man("Export JAVA_HOME", "Put export JAVA_HOME=/usr/lib/jvm/<your-jdk> in your shell profile and open a new terminal."),
      cmd("Check java", "java -version"),
    },
    confidence = "high",
  }
end)

E("java-class-version", {
  "unsupported class file major version (%d+)",
  "class file version (%d+)%.%d+",
  "unsupported major%.minor version (%d+)%.%d+",
}, function(c, _, m)
  local java = (tonumber(c[1]) or 0) - 44
  local cause
  if m.pi == 1 then
    cause = "A tool (Gradle, Kotlin, ASM, Lombok, jacoco) is older than the JDK running it: it cannot read Java " .. java .. " class files."
  else
    cause = "The code was compiled for Java " .. java .. " but the runtime is older."
  end
  return {
    title = "The JDK does not match the build (class file major " .. c[1] .. " = Java " .. java .. ")",
    cause = cause,
    steps = {
      cmd("Check the JDK in use", "java -version"),
      cmd("Check JAVA_HOME", "echo $JAVA_HOME"),
      man("Use a matching JDK", "Point JAVA_HOME at it, or pin it in the build: Gradle java { toolchain { languageVersion = JavaLanguageVersion.of(N) } }."),
    },
    confidence = "high",
  }
end)

E("jvm-dependency-unresolved", {
  "could not resolve ([%w_%.%-]+:[%w_%.%-]+[%w_:%.%-]*)",
  "could not resolve all [%a ]+ for configuration",
  "could not find ([%w_%.%-]+:[%w_%.%-]+:[%w_%.%-]+)",
  "could not find artifact ([^%s]+)",
}, function(c, ctx)
  local steps = {}
  if ctx.has("gradlew") then
    steps[#steps + 1] = cmd("Retry refreshing dependencies", "./gradlew build --refresh-dependencies")
  elseif ctx.has("build.gradle") or ctx.has("build.gradle.kts") then
    steps[#steps + 1] = cmd("Retry refreshing dependencies", "gradle build --refresh-dependencies")
  elseif ctx.has("pom.xml") then
    steps[#steps + 1] = cmd("Retry forcing an update", "mvn -U compile")
  end
  steps[#steps + 1] = man("Check the coordinates and the repositories", "The group:artifact:version must exist, and mavenCentral() (or your registry) must be declared.")
  steps[#steps + 1] = man("Check the network", "A proxy, VPN or offline mode makes every download fail.")
  return {
    title = c[1] and ("A dependency cannot be resolved: " .. c[1]) or "Dependencies cannot be resolved",
    cause = "The build could not download an artifact: wrong coordinates or version, a missing repository, or no network.",
    steps = steps,
    confidence = "medium",
  }
end)

-- ===== Flutter / Dart ====================================================================================

E("pubspec-missing", {
  'could not find a file named "pubspec%.yaml"',
}, function(_, _, m)
  local dir = m.line:match('in "([^"]+)"')
  return {
    title = "No pubspec.yaml here" .. (dir and (" (" .. dir .. ")") or ""),
    cause = "The command ran outside the Dart / Flutter project folder.",
    steps = {
      cmd("Find the project folder", "find . -maxdepth 3 -name pubspec.yaml"),
      man("Run the command from that folder", "cd into the one that holds pubspec.yaml."),
    },
    confidence = "high",
  }
end)

E("pub-version-solving", {
  "version solving failed",
}, function(_, _, m)
  local tool = m.lower:find("flutter", 1, true) and "flutter" or "dart"
  local because = m.text:match("[Bb]ecause ([^\n]+)", m.s)
  return {
    title = "pub cannot find compatible versions",
    cause = because and ("Because " .. trim(because):sub(1, 140)) or "Two dependencies (or the SDK constraint) require incompatible versions.",
    steps = {
      cmd("Try the newest compatible versions", tool .. " pub upgrade"),
      cmd("See what is outdated", tool .. " pub outdated"),
      man("Loosen the constraint the message blames", "Edit pubspec.yaml: widen the version range or the SDK constraint."),
    },
    confidence = "high",
  }
end)

E("android-licenses", {
  "licenses not accepted",
  "android license status unknown",
  "you have not accepted the license agreements",
}, function()
  return {
    title = "The Android SDK licenses are not accepted",
    cause = "The Android toolchain refuses to build until you accept the SDK licenses.",
    steps = {
      cmd("Accept the licenses", "flutter doctor --android-licenses", "Interactive: you read and accept each one."),
      cmd("Or with the SDK manager", "sdkmanager --licenses", "Needs the Android command-line tools and ANDROID_HOME set."),
    },
    confidence = "high",
  }
end)

E("cocoapods-missing", {
  "cocoapods not installed",
}, function()
  return {
    title = "CocoaPods is not installed",
    cause = "iOS / macOS builds resolve native dependencies with CocoaPods.",
    steps = {
      cmd("Install CocoaPods", "brew install cocoapods", "macOS only."),
      cmd("Check it works", "pod --version"),
    },
    confidence = "high",
  }
end)

-- ===== Docker ============================================================================================

E("docker-permission", {
  "permission denied while trying to connect to the docker daemon socket",
  "permission denied while trying to connect to the docker api",
}, function()
  return {
    title = "Your user cannot use the Docker socket",
    cause = "The socket belongs to the docker group and your user is not in it.",
    steps = {
      cmd("See your groups", "id -nG", "If docker is not listed, you are not in the group."),
      man("Add yourself to the docker group", "`sudo usermod -aG docker $USER`, then log out and in (or run `newgrp docker`)."),
    },
    confidence = "high",
  }
end)

E("docker-daemon-down", {
  "cannot connect to the docker daemon",
  "docker_engine: the system cannot find the file specified",
  "docker daemon is not running",
}, function(_, _, m)
  if m.ids["docker-permission"] then
    return nil
  end
  return {
    title = "The Docker daemon is not running",
    cause = "The docker client cannot reach the daemon: it is stopped, or Docker Desktop is closed.",
    steps = {
      cmd("Check the daemon", "docker info", "An error here confirms it is down."),
      cmd("Linux: see the service", "systemctl status docker"),
      man("Start it", "Linux: `sudo systemctl start docker`. macOS / Windows: open Docker Desktop (on WSL enable its WSL integration)."),
    },
    confidence = "high",
  }
end)

E("docker-port-allocated", {
  "bind for [^\n]-:(%d+) failed: port is already allocated",
  "ports are not available: [^\n]-:(%d+) ",
  "port is already allocated",
}, function(c)
  local port = c[1]
  local steps
  if port then
    steps = {
      cmd("Find the container holding it", "docker ps --filter publish=" .. port),
      cmd("Or the host process", "ss -ltnp 'sport = :" .. port .. "'"),
      man("Stop it or change the host port", 'In compose change the left side of ports (for example "' .. (tonumber(port) + 1) .. ":" .. port .. '").'),
    }
  else
    steps = {
      cmd("List the running containers", "docker ps"),
      man("Stop the one that holds the port or change the host side of ports"),
    }
  end
  return {
    title = port and ("Port " .. port .. " is already allocated") or "A published port is already allocated",
    cause = "Another container or a host process already publishes that port.",
    steps = steps,
    confidence = "high",
  }
end)

E("no-space-left", {
  "no space left on device",
}, function(_, _, m)
  local docker = m.lower:find("docker", 1, true) or m.lower:find("overlay", 1, true)
  local steps = {}
  if docker then
    steps[#steps + 1] = cmd("See what Docker uses", "docker system df")
  end
  steps[#steps + 1] = cmd("See free space and inodes", "df -h . && df -i .")
  if docker then
    steps[#steps + 1] = man("Remove unused data", "`docker image prune` / `docker builder prune` free space; review what they list first.")
  else
    steps[#steps + 1] = cmd("Find the biggest folders", "du -xsh ./* 2>/dev/null | sort -h | tail -5")
  end
  return {
    title = "The disk is full",
    cause = "A write failed because the device has no free space (or no free inodes).",
    steps = steps,
    confidence = "high",
  }
end)

-- ===== Generic runtime ===================================================================================

E("connection-refused", {
  "econnrefused[^\n]*:(%d+)",
  "dial tcp [^\n]-:(%d+): connect: connection refused",
  "port (%d+) failed: connection refused",
  "connect to [^\n]- port (%d+)[^\n]-connection refused",
  "connection refused[^\n]*:(%d+)",
}, function(c, ctx)
  local port = tonumber(c[1])
  local svc = PORT_SERVICES[port]
  local steps = {}
  if svc then
    if has_compose(ctx) then
      steps[#steps + 1] = cmd("Start " .. svc.name, "docker compose up -d " .. svc.svc, "The compose service name may differ: `docker compose config --services` lists them.")
    else
      steps[#steps + 1] = man("Start " .. svc.name, "Linux: `sudo systemctl start " .. svc.unit .. "`, or run it in Docker.")
    end
  end
  steps[#steps + 1] = cmd("See whether anything listens on " .. port, "ss -ltn 'sport = :" .. port .. "'", "Empty output means the service is not running.")
  steps[#steps + 1] = man("Check the host and port the app uses", "Look at .env / config; inside a container use the service name, not localhost.")
  return {
    title = svc and (svc.name .. " is not running on port " .. port) or ("Nothing is listening on port " .. port),
    cause = svc and ("The app tried to reach " .. svc.name .. " on port " .. port .. " and nothing answered.") or ("A connection to port " .. port .. " was refused: the service is down or listens elsewhere."),
    steps = steps,
    confidence = svc and "high" or "medium",
  }
end)

E("env-file-missing", {
  "open ([^%s:]*%.env[%w%._%-]*): no such file or directory",
  "enoent[^\n]-'([^']-%.env[%w%._%-]*)'",
  "filenotfounderror[^\n]-'([^']-%.env[%w%._%-]*)'",
  "env file ([^%s]-%.env[%w%._%-]*) not found",
}, function(c, ctx)
  local path = c[1]
  local dir = path:match("^(.*)/[^/]+$")
  local root = ctx.root and (ctx.root:gsub("/$", ""))
  local at_root = dir == nil or dir == "." or (root ~= nil and dir == root)
  local steps = {}
  if at_root and path:match("%.env$") then
    for _, ex in ipairs({ ".env.example", ".env.sample", ".env.template", ".env.dist" }) do
      if ctx.has(ex) then
        steps[#steps + 1] = cmd("Create .env from " .. ex, "cp -n " .. ex .. " .env", "Never overwrites an existing .env.")
        break
      end
    end
  end
  if #steps > 0 then
    steps[#steps + 1] = man("Fill in the values", "Ask the team for secrets; never commit .env.")
  else
    steps[#steps + 1] = man("Create " .. path, "Put the variables the app reads in it (the README or the code that reads them lists the names); never commit it.")
  end
  return {
    title = "The env file " .. path .. " does not exist",
    cause = "The app or compose reads an .env file that was never created on this machine.",
    steps = steps,
    confidence = "high",
  }
end)

E("missing-env-var", {
  "required environment variable ['\"`]?([A-Z][A-Z0-9_]+)",
  "missing environment variable ['\"`]?([A-Z][A-Z0-9_]+)",
  "environment variable not found: ([A-Z][A-Z0-9_]+)",
  "environment variable ['\"`]?([A-Z][A-Z0-9_]+)['\"`]? is not set",
  "environment variable ['\"`]?([A-Z][A-Z0-9_]+)['\"`]? is required",
  "set the ([A-Z][A-Z0-9_]+) environment variable",
  "the ([A-Z][A-Z0-9_]+) variable is not set",
  "keyerror: ['\"]([A-Z][A-Z0-9]*_[A-Z0-9_]+)['\"]",
  "([A-Z][A-Z0-9_]+): unbound variable",
  "([A-Z][A-Z0-9_]+): parameter not set",
  "([A-Z][A-Z0-9_]+): parameter null or not set",
  "process%.env%.([A-Z][A-Z0-9_]+) is undefined",
  "([A-Z][A-Z0-9]*_[A-Z0-9_]+) is not set",
}, function(c, ctx)
  local name = c[1]
  if name == "JAVA_HOME" then
    return nil
  end
  local steps = {}
  if ctx.has(".env.example") then
    steps[#steps + 1] = cmd("See what the example expects", "grep -n " .. shell_quote(name) .. " .env.example")
  end
  steps[#steps + 1] = man("Set " .. name .. " in .env (or your shell)", "Use the real value; ask the team if you do not have it. Never invent one.")
  steps[#steps + 1] = man("Restart the process", "Environment variables are read at startup.")
  return {
    title = "The environment variable " .. name .. " is not set",
    cause = "The program reads " .. name .. " and it is missing from the environment.",
    steps = steps,
    confidence = "high",
  }
end)

E("script-crlf", {
  "(%.?%.?/[^%s:]+): [^\n]-bad interpreter",
  "bad interpreter",
}, function(c)
  local path = c[1]
  if not path then
    return {
      title = "A script has Windows line endings",
      cause = "The shebang line ends in CRLF, so the system looks for an interpreter named 'bash\\r'.",
      steps = { man("Convert the script to LF line endings", "`sed -i 's/\\r$//' <script>`, and set `* text=auto eol=lf` in .gitattributes.") },
      confidence = "medium",
    }
  end
  return {
    title = "The script " .. path .. " has Windows line endings",
    cause = "The shebang line ends in CRLF, so the system looks for an interpreter named 'bash\\r'.",
    steps = {
      cmd("Confirm it", "file " .. shell_quote(path), "Look for 'with CRLF line terminators'."),
      cmd("Convert it to LF", "sed -i 's/\\r$//' " .. shell_quote(path), "Then set `* text=auto eol=lf` in .gitattributes so git does not bring it back."),
    },
    confidence = "high",
  }
end)

E("script-not-executable", {
  function(text, lower)
    local from = 1
    while true do
      local s = lower:find("permission denied", from, true)
      if not s then
        return nil
      end
      local _, le, line = line_bounds(text, s)
      local ll = line:lower()
      if
        not (
          ll:find("eacces", 1, true)
          or ll:find("docker", 1, true)
          or ll:find("publickey", 1, true)
          or ll:find("socket", 1, true)
          or ll:find("while trying", 1, true)
          or ll:find("errno", 1, true)
        )
      then
        local path = line:match("([^%s:]+): [Pp][Ee][Rr][Mm][Ii][Ss][Ss][Ii][Oo][Nn] [Dd][Ee][Nn][Ii][Ee][Dd]%s*$")
          or line:match("[Pp][Ee][Rr][Mm][Ii][Ss][Ss][Ii][Oo][Nn] [Dd][Ee][Nn][Ii][Ee][Dd]: (%S+)%s*$")
        if path and (path:find("/", 1, true) or path:find("%.%a+$")) then
          return s, { path }
        end
      end
      from = le + 2
    end
  end,
}, function(c)
  local path = c[1]
  return {
    title = "The script " .. path .. " is not executable",
    cause = "The file exists but its execute bit is off (common after a checkout, a zip or a copy from Windows).",
    steps = {
      cmd("Make it executable", "chmod +x " .. shell_quote(path), "Commit the mode with `git update-index --chmod=+x " .. shell_quote(path) .. "`."),
      cmd("Check the mode and owner", "ls -l " .. shell_quote(path), "If it is a folder or unreadable, the problem is different."),
    },
    confidence = "high",
  }
end)

E("py-permission", {
  "permissionerror: %[errno 13%] permission denied: ['\"]([^'\"]+)['\"]",
}, function(c)
  local path = c[1]
  local steps = {}
  if path:find("%.sh$") or path:find("^%./") then
    steps[#steps + 1] = cmd("Make it executable", "chmod +x " .. shell_quote(path), "Only if the code tries to run that file.")
  end
  steps[#steps + 1] = cmd("Check the mode and owner", "ls -ld " .. shell_quote(path))
  steps[#steps + 1] = man("Give your user access", "Fix the owner or mode instead of running the program as root.")
  return {
    title = "Python cannot access " .. path,
    cause = "The process user lacks the needed permission on that file or folder.",
    steps = steps,
    confidence = "medium",
  }
end)

E("command-not-found", {
  "command not found: ([%w_%.%+%-]+)",
  "([%w_%.%+%-]+): command not found%f[%z\n\r]",
  "sh: %d+: ([%w_%.%+%-]+): not found",
  "'([^']+)' is not recognized as an internal or external command",
  "spawn ([^%s]+) enoent",
  'exec: "([^"]+)": executable file not found',
}, function(c, ctx, m)
  local name = c[1]
  local l = name:lower()
  if not name:find("%w") or l:find("^python") or l:find("^pip") then
    return nil
  end
  if (l == "gcc" or l == "cc") and (m.ids["go-cgo-compiler"] or m.ids["rust-linker-missing"]) then
    return nil
  end
  local pm = pm_of(ctx)
  local f = {
    title = "'" .. name .. "' is not installed or not on PATH",
    cause = "The shell could not find that program.",
    confidence = "high",
  }
  if ctx.has("package.json") and not ctx.has("node_modules") then
    f.cause = "'" .. name .. "' is probably a dev dependency of this project and node_modules does not exist."
    f.steps = { cmd("Install the dependencies", pm.install, "Dev tools live in node_modules/.bin once installed.") }
    return f
  end
  if ctx.has("node_modules/.bin/" .. name) then
    f.cause = "'" .. name .. "' is installed in node_modules/.bin, which is not on PATH."
    f.steps = { cmd("Run it through the package manager", pm.exec .. " " .. shell_quote(name)) }
    return f
  end
  if APT[l] then
    f.steps = {
      cmd("Install it", "sudo apt install " .. APT[l], "Missing system program (Debian/Ubuntu); macOS: brew install " .. (APT[l] == "build-essential" and "gcc" or APT[l]) .. "."),
      cmd("Check it is found", "command -v " .. shell_quote(name)),
    }
  elseif l == "pnpm" or l == "yarn" then
    f.steps = {
      cmd("Enable it through corepack", "corepack enable", "Node ships corepack, which provides pnpm and yarn."),
      cmd("Check it is found", "command -v " .. l),
    }
  else
    f.steps = {
      man("Install " .. name, "Use your package manager or the tool's own installer."),
      cmd("Look at PATH", "echo $PATH | tr ':' '\\n'", "The folder that holds " .. name .. " must be listed."),
    }
    f.confidence = "medium"
  end
  return f
end)

E("path-missing", {
  "(%.?%.?/[^%s:]+): no such file or directory",
  "zsh: no such file or directory: (%S+)",
  "enoent: no such file or directory, %a+ '([^']+)'",
  "filenotfounderror: %[errno 2%] no such file or directory: '([^']+)'",
  "can't open file '([^']+)': %[errno 2%] no such file or directory",
  "open ([^%s:]+): no such file or directory",
}, function(c, _, m)
  local path = c[1]
  if path:find("%.env") or m.ids["script-crlf"] then
    return nil
  end
  local dir = path:match("^(.*)/[^/]+$")
  local steps = {}
  if path:match("package%.json$") then
    steps[#steps + 1] = man("Run the command from the project folder", "The one that contains package.json.")
  end
  steps[#steps + 1] = cmd("See where you are", "pwd")
  steps[#steps + 1] = cmd("List the folder the path expects", "ls -la " .. shell_quote(dir and dir ~= "" and dir or "."))
  steps[#steps + 1] = man("Fix the path", "Relative paths depend on where the command runs; letter case matters on Linux.")
  while #steps > 3 do
    table.remove(steps, 1)
  end
  return {
    title = "File not found: " .. path,
    cause = "The command needs a file that is not at that path: wrong directory, wrong name, or not generated yet.",
    steps = steps,
    confidence = "medium",
  }
end)

E("address-in-use", {
  "listen %a+ [^\n]-:(%d+): bind: address already in use",
  "address already in use[^\n]*:(%d+)",
  "port (%d+) is already in use",
  "port (%d+) is in use",
  "address already in use",
}, function(c, _, m)
  if m.ids["node-port-in-use"] or m.ids["docker-port-allocated"] then
    return nil
  end
  if m.line:lower():find("trying", 1, true) then
    return nil
  end
  local port = c[1]
  local steps
  if port then
    steps = {
      cmd("Find the process holding the port", "lsof -i :" .. port),
      cmd("Same, with ss", "ss -ltnp 'sport = :" .. port .. "'"),
      man("Stop it or choose another port"),
    }
  else
    steps = {
      cmd("List what listens on TCP", "ss -ltnp", "Look for the port your app binds."),
      man("Stop that process or choose another port"),
    }
  end
  return {
    title = port and ("Port " .. port .. " is already in use") or "The address is already in use",
    cause = "Another process (often an earlier run of this program) is bound to the same address.",
    steps = steps,
    confidence = port and "high" or "medium",
  }
end)

E("out-of-memory", {
  "java%.lang%.outofmemoryerror: ([^\n]+)",
  "cannot allocate memory",
  "fatal error: runtime: out of memory",
  "fatal error: out of memory",
  "killed process (%d+)",
  "oomkilled",
}, function(c, _, m)
  if m.ids["node-heap-oom"] then
    return nil
  end
  local jvm = m.pi == 1
  return {
    title = jvm and ("The JVM ran out of memory: " .. trim(c[1]):sub(1, 60)) or "The process ran out of memory",
    cause = jvm and "The Java heap (or metaspace) hit its limit." or "The system had no memory left for the process (or its container limit was hit).",
    steps = {
      cmd("See memory in use", "free -h"),
      jvm and man("Raise the JVM heap", "-Xmx2g in JAVA_OPTS / MAVEN_OPTS, or org.gradle.jvmargs=-Xmx2g in gradle.properties.")
        or man("Use less memory", "Lower build parallelism (make -j, cargo build -j, go build -p), add swap, or raise the container memory limit."),
    },
    confidence = "medium",
  }
end)

E("segfault", {
  "segmentation fault",
  "sigsegv",
}, function(_, ctx)
  local steps = {
    man("Get a backtrace", "Run the same command under `gdb --args <cmd>` (or lldb) and type `bt` after the crash."),
  }
  if ctx.has("package.json") and (ctx.pm == nil or ctx.pm == "npm" or ctx.pm == "pnpm") then
    steps[#steps + 1] = cmd("Rebuild native modules", (ctx.pm or "npm") .. " rebuild", "A native addon built for another Node version often crashes this way.")
  end
  steps[#steps + 1] = man("Suspects", "Infinite recursion (stack overflow), a native extension built for another runtime version, or a mismatched C library.")
  return {
    title = "The program crashed with a segmentation fault",
    cause = "It touched memory it does not own: native code, a broken extension, or a stack overflow.",
    steps = steps,
    confidence = "medium",
  }
end)

-- ===== Git ===============================================================================================

E("git-not-repo", {
  "fatal: not a git repository",
}, function()
  return {
    title = "This folder is not a git repository",
    cause = "git ran outside a repository (wrong directory, or it was never initialized).",
    steps = {
      cmd("See if a parent is a repository", "git rev-parse --show-toplevel", "An error means none is."),
      man("cd into the repository folder"),
      cmd("Or start a new one here", "git init", "Only if this folder should become a repository."),
    },
    confidence = "high",
  }
end)

E("git-conflict-markers", {
  "conflict %(%a+%): merge conflict in ([^\n]+)",
  "automatic merge failed; fix conflicts",
  "you need to resolve your current index first",
  "you have unmerged paths",
  function(text, lower)
    local function at_line_start(marker)
      if lower:sub(1, #marker) == marker then
        return 1
      end
      local s = lower:find("\n" .. marker, 1, true)
      return s and (s + 1) or nil
    end
    local s = at_line_start("<<<<<<< ")
    if s and at_line_start(">>>>>>> ") then
      return s, {}
    end
    return nil
  end,
}, function(c)
  return {
    title = c[1] and ("Merge conflict in " .. trim(c[1])) or "Merge conflicts are unresolved",
    cause = "Git could not merge some changes automatically; the files hold <<<<<<< / ======= / >>>>>>> markers.",
    steps = {
      man("Resolve them with the conflict assistant", "Open the conflicted file and use <leader>Gx… (the conflict assistant)."),
      cmd("List the files still in conflict", "git diff --name-only --diff-filter=U"),
      man("Finish", "`git add` the resolved files, then `git merge --continue` (or `git rebase --continue`)."),
    },
    confidence = "high",
  }
end)

E("git-overwrite", {
  "your local changes to the following files would be overwritten by (%a+)",
  "untracked working tree files would be overwritten by (%a+)",
  "your local changes would be overwritten by (%a+)",
}, function(c, _, m)
  local op = c[1]
  if m.pi == 2 then
    return {
      title = "Untracked files would be overwritten by " .. op,
      cause = "Files in your folder that git does not track exist in the incoming branch too.",
      steps = {
        cmd("See the files", "git status --short"),
        man("Move or commit them", "Move the listed files away (or add and commit them), then repeat the " .. op .. "."),
      },
      confidence = "high",
    }
  end
  return {
    title = "Local changes would be overwritten by " .. op,
    cause = "You have uncommitted edits in files the " .. op .. " has to change.",
    steps = {
      cmd("See your changes", "git status --short"),
      cmd("Put them aside", 'git stash push -m "wip before ' .. op .. '"', "Saves your edits; bring them back with `git stash pop` after the " .. op .. "."),
      man("Or commit them first"),
    },
    confidence = "high",
  }
end)

-- Last on purpose: only when nothing more specific explained the failure.
E("npm-elifecycle", {
  "elifecycle",
}, function(_, ctx, m)
  if m.nfound > 0 then
    return nil
  end
  local pm = pm_of(ctx)
  local script = m.text:match("[Ee][Rr][Rr]!? [^\n]-@[^%s]+ ([%w:_%-]+): ")
  local steps = {
    man("Read the output above this line", "The script's own error (compiler, test, lint) is the real cause; ELIFECYCLE only says it exited non-zero."),
  }
  if script then
    steps[#steps + 1] = cmd("Run that script alone", pm.run .. " " .. script, "Shows its full output without the package manager noise.")
  end
  return {
    title = "An npm script failed" .. (script and (": " .. script) or ""),
    cause = "The package manager reports that a script exited with an error; the reason is printed before this line.",
    steps = steps,
    confidence = "medium",
  }
end)

---------------------------------------------------------------------------------------------------------------------
-- Compilation and the entry point
---------------------------------------------------------------------------------------------------------------------

for _, e in ipairs(ENTRIES) do
  e.compiled = {}
  for _, p in ipairs(e.patterns) do
    if type(p) == "function" then
      e.compiled[#e.compiled + 1] = { fn = p }
    else
      e.compiled[#e.compiled + 1] = { cp = ci(p), lit = literal(p) }
    end
  end
end

--- First pattern of the entry (they are listed most specific first) that matches, at its first occurrence:
--- { s, caps, pi } or nil.
local function match_entry(e, text, lower)
  for i, pt in ipairs(e.compiled) do
    local s, caps
    if pt.fn then
      s, caps = pt.fn(text, lower)
    elseif not pt.lit or lower:find(pt.lit, 1, true) then
      local r = { text:find(pt.cp) }
      if r[1] then
        s, caps = r[1], { unpack(r, 3) }
      end
    end
    if s then
      return { s = s, caps = caps or {}, pi = i }
    end
  end
  return nil
end

---@return string[]
function M.ids()
  local out = {}
  for _, e in ipairs(ENTRIES) do
    out[#out + 1] = e.id
  end
  return out
end

---@param text string
---@param ctx table?
---@return table[]
function M.find(text, ctx)
  if type(text) ~= "string" or text == "" then
    return {}
  end
  ctx = ctx or {}
  local c = {
    has = type(ctx.has) == "function" and ctx.has or function()
      return false
    end,
    pm = ctx.pm,
    root = ctx.root,
  }
  local lower = text:lower()
  local out, ids = {}, {}
  for _, e in ipairs(ENTRIES) do
    if #out >= MAX then
      break
    end
    local hit = match_entry(e, text, lower)
    if hit then
      local _, _, line = line_bounds(text, hit.s)
      local m = { s = hit.s, pi = hit.pi, text = text, lower = lower, line = line, ids = ids, nfound = #out }
      local f = e.build(hit.caps, c, m)
      if f then
        f.id = e.id
        f.evidence = evidence_of(text, hit.s)
        while #f.steps > 3 do
          table.remove(f.steps)
        end
        ids[e.id] = true
        out[#out + 1] = f
      end
    end
  end
  return out
end

return M
