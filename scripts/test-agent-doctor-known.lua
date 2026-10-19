-- Tests of the known problems of the troubleshooting agent (nvim/lua/agent/doctor/known.lua): one realistic sample per
-- entry (right id, the captured value in title / steps, the package manager's commands), negative cases, limits and speed.
-- Hermetic: pure module, no network, no tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "set rtp+=$PWD/nvim" -c "luafile scripts/test-agent-doctor-known.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if not vim.deep_equal(got, want) then
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end

local known = require("agent.doctor.known")

local function ctx_of(files, pm)
  local set = {}
  for _, f in ipairs(files or {}) do
    set[f] = true
  end
  return {
    has = function(p)
      return set[p] == true
    end,
    pm = pm,
    root = "/proj",
  }
end

local function get(list, id)
  for _, f in ipairs(list) do
    if f.id == id then
      return f
    end
  end
end
local function ids_of(list)
  local o = {}
  for _, f in ipairs(list) do
    o[#o + 1] = f.id
  end
  return o
end
local function runs(f)
  local o = {}
  for _, s in ipairs(f and f.steps or {}) do
    if s.run then
      o[#o + 1] = s.run
    end
  end
  return table.concat(o, "\n")
end
local function blob(f)
  local o = { f.title, f.cause }
  for _, s in ipairs(f.steps) do
    o[#o + 1] = s.title
    o[#o + 1] = s.run or ""
    o[#o + 1] = s.note or ""
  end
  return table.concat(o, "\n")
end

--- Finds `id` in the result of `text` and returns it (failing the test when it is missing).
local function expect(name, id, text, ctx)
  local list = known.find(text, ctx or ctx_of())
  local f = get(list, id)
  ok(name .. " finds " .. id .. " (got " .. table.concat(ids_of(list), ",") .. ")", f ~= nil)
  return f or { title = "", cause = "", steps = {}, evidence = "" }
end
local function absent(name, id, text, ctx)
  local list = known.find(text, ctx or ctx_of())
  ok(name .. " does not find " .. id .. " (got " .. table.concat(ids_of(list), ",") .. ")", get(list, id) == nil)
end
local function has_text(name, s, needle)
  ok(name .. ": '" .. needle .. "' in " .. vim.inspect(s), s:find(needle, 1, true) ~= nil)
end

---------------------------------------------------------------------------------------------------------------------
-- Node / JS / TS
---------------------------------------------------------------------------------------------------------------------

local f = expect("ts alias", "ts-module-not-found", "src/a.ts(3,20): error TS2307: Cannot find module '@/lib/db' or its corresponding type declarations.")
has_text("ts alias", f.title, "@/lib/db")
has_text("ts alias", blob(f), "tsconfig")
f = expect("ts relative", "ts-module-not-found", "src/a.ts(1,8): error TS2307: Cannot find module './util' or its corresponding type declarations.")
has_text("ts relative", f.title, "./util")
f = expect(
  "ts package, node_modules present",
  "ts-module-not-found",
  "src/a.ts(1,19): error TS2307: Cannot find module 'zod' or its corresponding type declarations.",
  ctx_of({ "node_modules" }, "pnpm")
)
has_text("ts package pnpm", runs(f), "pnpm add zod")
f = expect(
  "ts package types",
  "ts-module-not-found",
  "error TS2307: Cannot find module 'lodash' or its corresponding type declarations.",
  ctx_of({ "node_modules", "node_modules/lodash" }, "npm")
)
has_text("ts types", runs(f), "npm install -D @types/lodash")
f = expect(
  "ts node_modules absent",
  "ts-module-not-found",
  "error TS2307: Cannot find module 'react' or its corresponding type declarations.",
  ctx_of({}, "yarn")
)
eq("ts absent install", runs(f), "yarn")
absent("ts2307 is not a node-module-missing", "node-module-missing", "error TS2307: Cannot find module 'zod' or its corresponding type declarations.")

f = expect("node module (node_modules present)", "node-module-missing", "node:internal/modules/cjs/loader:1080\n  throw err;\n  ^\n\nError: Cannot find module 'express'\nRequire stack:\n- /app/server.js", ctx_of({ "node_modules" }, "pnpm"))
has_text("node module", f.title, "express")
has_text("node module pnpm", runs(f), "pnpm add express")
f = expect("node module (no node_modules)", "node-module-missing", "Error: Cannot find module 'express'\nRequire stack:\n- /app/server.js", ctx_of({}, "pnpm"))
eq("node module installs all with pnpm", runs(f), "pnpm install")
f = expect("node module npm", "node-module-missing", "Error: Cannot find module '@nestjs/core/common'", ctx_of({ "node_modules" }, "npm"))
has_text("scoped module root", runs(f), "npm install @nestjs/core")
f = expect("ERR_MODULE_NOT_FOUND", "node-module-missing", "Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'chalk' imported from /app/src/index.js", ctx_of({ "node_modules" }, "npm"))
has_text("esm package", f.title, "chalk")
f = expect("vite import", "node-module-missing", '[vite] Internal server error: Failed to resolve import "axios" from "src/api.ts". Does the file exist?', ctx_of({ "node_modules" }, "bun"))
has_text("vite import bun", runs(f), "bun add axios")
f = expect("webpack", "node-module-missing", "Module not found: Error: Can't resolve 'moment' in '/app/src'", ctx_of({ "node_modules" }, "yarn"))
has_text("webpack yarn", runs(f), "yarn add moment")
f = expect("node path module", "node-module-missing", "Error: Cannot find module '/app/dist/index.js'")
eq("path module is manual", runs(f), "")

f = expect("esm/cjs", "node-esm-cjs", "(node:123) Warning: To load an ES module, set \"type\": \"module\"\n/app/a.js:1\nimport x from 'x'\n^^^^^^\nSyntaxError: Cannot use import statement outside a module")
has_text("esm/cjs", blob(f), "type")

f = expect("EADDRINUSE", "node-port-in-use", "node:events:495\n      throw er; // Unhandled 'error' event\nError: listen EADDRINUSE: address already in use :::3000\n    at Server.setupListenHandle")
has_text("port title", f.title, "3000")
has_text("lsof", runs(f), "lsof -i :3000")
has_text("ss", runs(f), "ss -ltnp 'sport = :3000'")
f = expect("EADDRINUSE ipv4", "node-port-in-use", "Error: listen EADDRINUSE: address already in use 127.0.0.1:8080")
has_text("port ipv4", f.title, "8080")
absent("EADDRINUSE without port", "node-port-in-use", "the word eaddrinuse alone, no number")

f = expect("ERESOLVE", "npm-eresolve", "npm error code ERESOLVE\nnpm error ERESOLVE unable to resolve dependency tree\nnpm error Found: react@18.2.0\nnpm error Could not resolve dependency:\nnpm error peer react@\"^17.0.0\" from react-foo@2.0.0")
has_text("eresolve", runs(f), "npm install --legacy-peer-deps")
has_text("eresolve peer", f.cause, "react-foo@2.0.0")

f = expect("engine", "node-engine-mismatch", "npm WARN EBADENGINE Unsupported engine {\nnpm WARN EBADENGINE   package: 'vite@5.0.0',\nnpm WARN EBADENGINE   required: { node: '^18.0.0 || >=20.0.0' },", ctx_of({ ".nvmrc" }))
has_text("engine nvm", runs(f), "nvm use")
f = expect("engine yarn", "node-engine-mismatch", 'error vite@5.0.0: The engine "node" is incompatible with this module. Expected version ">=18". Got "16.20.0"', ctx_of({}))
has_text("engine expected", f.title, ">=18")
f = expect("vite engine", "node-engine-mismatch", "You are using Node.js 16.20.0. Vite requires Node.js version 18+. Please upgrade Node.js.", ctx_of({ ".node-version" }))
has_text("engine node-version", runs(f), "cat .node-version")

f = expect("inotify", "inotify-limit", "Error: ENOSPC: System limit for number of file watchers reached, watch '/app/src'")
has_text("inotify", runs(f), "sysctl fs.inotify.max_user_watches")
absent("inotify is not disk full", "no-space-left", "Error: ENOSPC: System limit for number of file watchers reached, watch '/app/src'")

f = expect("EACCES global", "npm-eacces", "npm ERR! code EACCES\nnpm ERR! syscall mkdir\nnpm ERR! path /usr/lib/node_modules/typescript\nnpm ERR! Error: EACCES: permission denied, mkdir '/usr/lib/node_modules/typescript'")
has_text("eacces global", runs(f), "npm config set prefix")
f = expect("EACCES local", "npm-eacces", "npm ERR! Error: EACCES: permission denied, open '/home/u/proj/node_modules/.cache/x'")
has_text("eacces local", runs(f), "ls -ld /home/u/proj/node_modules/.cache/x")
absent("EACCES is not a script", "script-not-executable", "npm ERR! Error: EACCES: permission denied, open '/home/u/proj/node_modules/.cache/x'")

f = expect("heap oom", "node-heap-oom", "<--- Last few GCs --->\nFATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory")
has_text("heap oom", blob(f), "NODE_OPTIONS=--max-old-space-size=4096")
absent("heap oom is not the generic one", "out-of-memory", "FATAL ERROR: Reached heap limit Allocation failed - JavaScript heap out of memory")

-- ELIFECYCLE: only alone
f = expect("elifecycle alone", "npm-elifecycle", "npm ERR! code ELIFECYCLE\nnpm ERR! errno 2\nnpm ERR! my-app@1.0.0 build: `tsc -b`\nnpm ERR! Exit status 2", ctx_of({}, "pnpm"))
has_text("elifecycle script", runs(f), "pnpm run build")
absent("elifecycle with a cause", "npm-elifecycle", "Error: Cannot find module 'express'\nnpm ERR! code ELIFECYCLE", ctx_of({ "node_modules" }))

---------------------------------------------------------------------------------------------------------------------
-- Python
---------------------------------------------------------------------------------------------------------------------

local TB = 'Traceback (most recent call last):\n  File "app.py", line 1, in <module>\n    import requests\nModuleNotFoundError: No module named \'requests\''
f = expect("py module (requirements)", "py-module-missing", TB, ctx_of({ "requirements.txt" }))
has_text("py module", f.title, "requests")
has_text("py venv", runs(f), "python3 -m venv .venv")
has_text("py requirements", runs(f), "pip install -r requirements.txt")
f = expect("py module (venv exists)", "py-module-missing", TB, ctx_of({ ".venv", "requirements.txt" }))
has_text("py existing venv", runs(f), ". .venv/bin/activate && pip install -r requirements.txt")
f = expect("py module (no requirements)", "py-module-missing", 'ModuleNotFoundError: No module named \'yaml\'', ctx_of({}))
has_text("py pip name", runs(f), "pip install pyyaml")
f = expect("py module submodule", "py-module-missing", "ModuleNotFoundError: No module named 'django.db'", ctx_of({ "pyproject.toml" }))
has_text("py pyproject", runs(f), "pip install -e .")
f = expect("py local module", "py-module-missing", "ModuleNotFoundError: No module named 'utils'", ctx_of({ "utils.py" }))
has_text("py local", f.cause, "local module")

f = expect("externally managed", "py-externally-managed", "error: externally-managed-environment\n\n× This environment is externally managed\n╰─> To install Python packages system-wide, try apt install")
has_text("externally managed", runs(f), "python3 -m venv .venv")

f = expect("python not found", "python-not-found", "zsh: command not found: python")
has_text("python not found", runs(f), "python3 --version")
absent("python is not generic command-not-found", "command-not-found", "zsh: command not found: python")
f = expect("pip not found", "python-not-found", "bash: pip: command not found")
has_text("pip not found", runs(f), "python3 -m pip --version")

f = expect("indentation", "py-indentation", '  File "/app/main.py", line 12\n    return x\n    ^\nIndentationError: unexpected indent')
has_text("indentation", f.title, "main.py:12")
f = expect("taberror", "py-indentation", '  File "m.py", line 5\n    x = 1\nTabError: inconsistent use of tabs and spaces in indentation')
has_text("taberror grep", runs(f), "grep -nP")

f = expect("syntax error", "py-syntax-error", '  File "/app/old.py", line 3\n    print "hello"\n          ^\nSyntaxError: Missing parentheses in call to \'print\'. Did you mean print(...)?')
has_text("syntax error", f.title, "/app/old.py:3")
absent("js syntax error is not python's", "py-syntax-error", "/app/a.js:1\nconst x = ;\n          ^\nSyntaxError: Unexpected token ';'")

---------------------------------------------------------------------------------------------------------------------
-- Go
---------------------------------------------------------------------------------------------------------------------

f = expect("go.sum", "go-missing-sum", "main.go:5:2: missing go.sum entry for module providing package github.com/gin-gonic/gin (imported by example.com/app); to add:\n\tgo get example.com/app")
has_text("go.sum", f.title, "github.com/gin-gonic/gin")
eq("go.sum run", f.steps[1].run, "go mod tidy")
f = expect("go.sum short", "go-missing-sum", "go: github.com/x/y@v1.0.0: missing go.sum entry; to add it:\n\tgo mod download github.com/x/y")
has_text("go.sum short", runs(f), "go mod tidy")

f = expect("go mod tidy", "go-mod-tidy", "go: updates to go.mod needed; to update it:\n\tgo mod tidy")
has_text("go mod tidy", runs(f), "go mod tidy")
f = expect("go no required module", "go-mod-tidy", "main.go:4:2: no required module provides package github.com/spf13/cobra; to add it:\n\tgo get github.com/spf13/cobra")
has_text("go get", runs(f), "go get github.com/spf13/cobra")

f = expect("cgo", "go-cgo-compiler", '# github.com/mattn/go-sqlite3\ncgo: C compiler "gcc" not found: exec: "gcc": executable file not found in $PATH')
has_text("cgo", runs(f), "build-essential")
has_text("cgo no-cgo", runs(f), "CGO_ENABLED=0")
absent("cgo is not command-not-found gcc", "command-not-found", 'cgo: C compiler "gcc" not found: exec: "gcc": executable file not found in $PATH')

f = expect("build constraints", "go-build-constraints", "package example.com/app/winonly: build constraints exclude all Go files in /home/u/app/winonly")
has_text("build constraints", f.title, "/home/u/app/winonly")

f = expect("not in std", "go-not-in-std", "main.go:4:2: package github.com/x/y is not in std (/usr/local/go/src/github.com/x/y)")
has_text("not in std", f.title, "github.com/x/y")
f = expect("slices not in std", "go-not-in-std", "main.go:5:2: package slices is not in GOROOT (/usr/lib/go-1.19/src/slices)")
has_text("slices go version", runs(f), "go version")

f = expect("go unused var", "go-unused", "./main.go:8:2: declared and not used: count")
has_text("go unused var", f.title, "variable count")
f = expect("go unused var old", "go-unused", "./main.go:8:2: count declared but not used")
has_text("go unused var old", f.title, "count")
f = expect("go unused import", "go-unused", './main.go:4:2: "os" imported and not used')
has_text("go unused import", f.title, "import os")
eq("go unused is manual", runs(f), "")

f = expect("go panic", "go-panic", "panic: runtime error: invalid memory address or nil pointer dereference\n[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x4a2b3c]\n\ngoroutine 1 [running]:\nmain.run(...)\n\t/home/u/app/main.go:21\nmain.main()\n\t/home/u/app/main.go:12 +0x1d\nexit status 2")
has_text("go panic frame", blob(f), "/home/u/app/main.go:21")
has_text("go panic cause", f.cause, "nil pointer")
absent("go panic is not the generic segfault", "segfault", "panic: runtime error: index out of range [3] with length 3")

---------------------------------------------------------------------------------------------------------------------
-- Rust
---------------------------------------------------------------------------------------------------------------------

f = expect("rust linker", "rust-linker-missing", "error: linker `cc` not found\n  |\n  = note: No such file or directory (os error 2)")
has_text("rust linker", runs(f), "build-essential")
absent("rust linker is not command-not-found cc", "command-not-found", "error: linker `cc` not found")

f = expect("openssl", "rust-openssl", "error: failed to run custom build command for `openssl-sys v0.9.99`\n\nCaused by:\n  Could not find directory of OpenSSL installation, and this `-sys` crate cannot proceed without this knowledge.")
has_text("openssl", runs(f), "libssl-dev")
has_text("openssl vendored", runs(f), "--features vendored")

f = expect("unresolved import", "rust-unresolved-import", "error[E0432]: unresolved import `serde`\n --> src/main.rs:1:5\n  |\n1 | use serde::Serialize;\n  |     ^^^^^ use of undeclared crate or module `serde`")
has_text("unresolved import", f.title, "serde")
has_text("unresolved add", runs(f), "cargo add serde")
f = expect("unresolved crate path", "rust-unresolved-import", "error[E0432]: unresolved import `crate::models::User`")
eq("unresolved crate path is manual", runs(f), "")

f = expect("no matching package", "rust-no-matching-package", "error: no matching package named `serdee` found\nlocation searched: registry `crates-io`\nrequired by package `app v0.1.0`")
has_text("no matching", runs(f), "cargo search serdee")

f = expect("edition", "rust-toolchain-old", "error: failed to parse manifest at `/a/Cargo.toml`\n\nCaused by:\n  feature `edition2024` is required\n\n  The package requires the Cargo feature called `edition2024`, but that feature is not stabilized in this version of Cargo (1.80.0)")
has_text("edition", runs(f), "rustup update stable")
f = expect("lock version", "rust-toolchain-old", "error: lock file version 4 was found, but this version of Cargo does not support it")
has_text("lock version", f.cause, "lock file version 4")

f = expect("rust panic", "rust-panic", "thread 'main' panicked at src/main.rs:10:5:\ncalled `Option::unwrap()` on a `None` value\nnote: run with `RUST_BACKTRACE=1` environment variable")
has_text("rust panic", f.title, "src/main.rs:10:5")

---------------------------------------------------------------------------------------------------------------------
-- Java / Kotlin / Gradle
---------------------------------------------------------------------------------------------------------------------

f = expect("JAVA_HOME unset", "java-home", "ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.")
has_text("JAVA_HOME", runs(f), "ls /usr/lib/jvm")
absent("JAVA_HOME is not a generic env var", "missing-env-var", "ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.")
f = expect("JAVA_HOME invalid", "java-home", "ERROR: JAVA_HOME is set to an invalid directory: /usr/lib/jvm/old\n\nPlease set the JAVA_HOME variable")
has_text("JAVA_HOME invalid", f.title, "/usr/lib/jvm/old")

f = expect("class version", "java-class-version", "java.lang.IllegalArgumentException: Unsupported class file major version 65\n\tat org.gradle.internal.classanalysis.AsmConstants")
has_text("class version", f.title, "Java 21")
f = expect("class runtime older", "java-class-version", "Exception in thread \"main\" java.lang.UnsupportedClassVersionError: com/x/App has been compiled by a more recent version of the Java Runtime (class file version 61.0), this version of the Java Runtime only recognizes class file versions up to 55.0")
has_text("class runtime", f.title, "Java 17")

f = expect("gradle resolve", "jvm-dependency-unresolved", "> Could not resolve com.squareup.okhttp3:okhttp:4.12.0.\n  Required by:\n      project :app\n   > Could not GET 'https://repo.maven.apache.org/x'", ctx_of({ "gradlew" }))
has_text("gradle resolve", f.title, "com.squareup.okhttp3:okhttp:4.12.0")
has_text("gradlew refresh", runs(f), "./gradlew build --refresh-dependencies")
f = expect("maven resolve", "jvm-dependency-unresolved", "[ERROR] Failed to execute goal: Could not find artifact org.foo:bar:jar:1.0 in central (https://repo.maven.apache.org/maven2)", ctx_of({ "pom.xml" }))
has_text("mvn -U", runs(f), "mvn -U compile")
absent("npm 'could not resolve dependency' is not gradle", "jvm-dependency-unresolved", "npm error Could not resolve dependency:\nnpm error peer react@\"^17\" from foo@1.0.0")

---------------------------------------------------------------------------------------------------------------------
-- Flutter / Dart
---------------------------------------------------------------------------------------------------------------------

f = expect("pubspec", "pubspec-missing", 'Could not find a file named "pubspec.yaml" in "/home/u/work".')
has_text("pubspec dir", f.title, "/home/u/work")
has_text("pubspec find", runs(f), "find . -maxdepth 3 -name pubspec.yaml")

f = expect("version solving", "pub-version-solving", "Because app depends on flutter_bloc ^9.0.0 which requires bloc ^9.0.0, version solving failed.\nflutter pub get failed")
has_text("version solving", runs(f), "flutter pub upgrade")
f = expect("version solving dart", "pub-version-solving", "Resolving dependencies...\nBecause foo >=2.0.0 depends on bar ^3.0.0, version solving failed.")
has_text("version solving dart", runs(f), "dart pub upgrade")

f = expect("android licenses", "android-licenses", "[!] Android toolchain - develop for Android devices (Android SDK version 34.0.0)\n    ✗ Some Android licenses not accepted. To resolve this, run: flutter doctor --android-licenses")
has_text("android licenses", runs(f), "flutter doctor --android-licenses")

f = expect("cocoapods", "cocoapods-missing", "Warning: CocoaPods not installed. Skipping pod install.\n  CocoaPods is a package manager for iOS or macOS platform code.")
has_text("cocoapods", runs(f), "brew install cocoapods")

---------------------------------------------------------------------------------------------------------------------
-- Docker
---------------------------------------------------------------------------------------------------------------------

f = expect("docker down", "docker-daemon-down", "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?")
has_text("docker down", runs(f), "docker info")
f = expect("docker permission", "docker-permission", "permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Get \"http://%2Fvar%2Frun%2Fdocker.sock/v1.24/containers/json\": dial unix /var/run/docker.sock: connect: permission denied")
has_text("docker permission", blob(f), "usermod -aG docker")
absent("docker permission is not daemon down", "docker-daemon-down", "permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock")
absent("docker permission is not a script", "script-not-executable", "permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock")

f = expect("port allocated", "docker-port-allocated", "Error response from daemon: driver failed programming external connectivity on endpoint db: Bind for 0.0.0.0:5432 failed: port is already allocated")
has_text("port allocated", f.title, "5432")
has_text("port allocated cmd", runs(f), "docker ps --filter publish=5432")
f = expect("ports not available", "docker-port-allocated", "Error response from daemon: Ports are not available: exposing port TCP 0.0.0.0:8080 -> 0.0.0.0:0: listen tcp 0.0.0.0:8080: bind: address already in use")
has_text("ports not available", f.title, "8080")
absent("docker port is not generic address in use", "address-in-use", "Bind for 0.0.0.0:5432 failed: port is already allocated")

f = expect("disk full", "no-space-left", "write /tmp/out.o: no space left on device")
has_text("disk full", runs(f), "df -h")
f = expect("docker disk full", "no-space-left", "failed to register layer: write /var/lib/docker/overlay2/x/diff/a: no space left on device\ndocker: error")
has_text("docker disk full", runs(f), "docker system df")

---------------------------------------------------------------------------------------------------------------------
-- Generic runtime
---------------------------------------------------------------------------------------------------------------------

f = expect("postgres refused", "connection-refused", "Error: connect ECONNREFUSED 127.0.0.1:5432\n    at TCPConnectWrap.afterConnect", ctx_of({ "docker-compose.yml" }))
has_text("postgres refused", f.title, "PostgreSQL")
has_text("postgres compose", runs(f), "docker compose up -d postgres")
f = expect("redis refused ipv6", "connection-refused", "Error: connect ECONNREFUSED ::1:6379", ctx_of({}))
has_text("redis", f.title, "Redis")
ok("no compose: no compose command", not runs(f):find("docker compose", 1, true))
f = expect("go dial", "connection-refused", 'failed to connect: dial tcp 127.0.0.1:27017: connect: connection refused', ctx_of({ "compose.yaml" }))
has_text("mongo", runs(f), "docker compose up -d mongo")
f = expect("psql refused", "connection-refused", 'psql: error: connection to server at "localhost" (127.0.0.1), port 5432 failed: Connection refused\n\tIs the server running on that host and accepting TCP/IP connections?', ctx_of({}))
has_text("psql refused", f.title, "5432")
f = expect("curl refused", "connection-refused", "curl: (7) Failed to connect to localhost port 9200 after 0 ms: Connection refused", ctx_of({}))
has_text("elasticsearch", f.title, "Elasticsearch")
f = expect("rabbit", "connection-refused", "pika.exceptions.AMQPConnectionError: ECONNREFUSED 127.0.0.1:5672", ctx_of({ "docker-compose.yml" }))
has_text("rabbit", runs(f), "docker compose up -d rabbitmq")
f = expect("mysql", "connection-refused", "Error: connect ECONNREFUSED 127.0.0.1:3306", ctx_of({ "compose.yml" }))
has_text("mysql", runs(f), "docker compose up -d mysql")
f = expect("unknown port", "connection-refused", "Error: connect ECONNREFUSED 127.0.0.1:4000", ctx_of({}))
has_text("unknown port", f.title, "4000")
eq("unknown port confidence", f.confidence, "medium")
absent("refused without a port", "connection-refused", "ConnectionRefusedError: [Errno 111] Connection refused")

f = expect("env file go", "env-file-missing", "open .env: no such file or directory", ctx_of({ ".env.example" }))
eq("env file cp", f.steps[1].run, "cp -n .env.example .env")
f = expect("env file node", "env-file-missing", "Error: ENOENT: no such file or directory, open '/proj/.env'", ctx_of({ ".env.example" }))
has_text("env node cp", runs(f), "cp -n .env.example .env")
f = expect("env file compose", "env-file-missing", "env file /proj/.env not found: stat /proj/.env: no such file or directory", ctx_of({}))
eq("env file manual", runs(f), "")
absent("env file is not a generic path", "path-missing", "open .env: no such file or directory")

f = expect("env var required", "missing-env-var", "Error: Missing required environment variable DATABASE_URL", ctx_of({ ".env.example" }))
has_text("env var", f.title, "DATABASE_URL")
has_text("env var example", runs(f), "grep -n DATABASE_URL .env.example")
has_text("env var manual", blob(f), "Never invent")
f = expect("env var KeyError", "missing-env-var", "Traceback (most recent call last):\n  File \"settings.py\", line 4, in <module>\n    SECRET = os.environ['SECRET_KEY']\nKeyError: 'SECRET_KEY'")
has_text("KeyError", f.title, "SECRET_KEY")
f = expect("env compose", "missing-env-var", "WARN[0000] The STRIPE_KEY variable is not set. Defaulting to a blank string.")
has_text("compose var", f.title, "STRIPE_KEY")
f = expect("env prisma", "missing-env-var", "Error: Environment variable not found: DATABASE_URL.")
has_text("prisma var", f.title, "DATABASE_URL")
f = expect("env bash", "missing-env-var", "./run.sh: line 3: API_TOKEN: unbound variable")
has_text("bash var", f.title, "API_TOKEN")
f = expect("env is not set", "missing-env-var", "RuntimeError: REDIS_URL is not set")
has_text("is not set", f.title, "REDIS_URL")
absent("lowercase KeyError is a normal dict key", "missing-env-var", "KeyError: 'name'")

f = expect("crlf", "script-crlf", "bash: ./deploy.sh: /bin/bash^M: bad interpreter: No such file or directory")
has_text("crlf", runs(f), "sed -i 's/\\r$//' ./deploy.sh")
absent("crlf is not a missing path", "path-missing", "bash: ./deploy.sh: /bin/bash^M: bad interpreter: No such file or directory")

f = expect("not executable", "script-not-executable", "bash: ./run.sh: Permission denied")
has_text("chmod", runs(f), "chmod +x ./run.sh")
f = expect("not executable zsh", "script-not-executable", "zsh: permission denied: ./scripts/build.sh")
has_text("chmod zsh", runs(f), "chmod +x ./scripts/build.sh")
f = expect("not executable go", "script-not-executable", "fork/exec /tmp/tool: permission denied")
has_text("chmod go", runs(f), "chmod +x /tmp/tool")
absent("ssh permission denied is not a script", "script-not-executable", "git@github.com: Permission denied (publickey).")
absent("plain permission denied sentence", "script-not-executable", "Operation failed: permission denied")

f = expect("py permission", "py-permission", "PermissionError: [Errno 13] Permission denied: '/var/log/app.log'")
has_text("py permission", runs(f), "ls -ld /var/log/app.log")
f = expect("py permission script", "py-permission", "PermissionError: [Errno 13] Permission denied: './run.sh'")
has_text("py permission chmod", runs(f), "chmod +x ./run.sh")

f = expect("command not found zsh", "command-not-found", "zsh: command not found: jq")
has_text("jq", runs(f), "sudo apt install jq")
f = expect("command not found bash", "command-not-found", "bash: line 1: cmake: command not found")
has_text("cmake", runs(f), "sudo apt install cmake")
f = expect("sh not found, deps missing", "command-not-found", "sh: 1: tsc: not found\n npm ERR! code ELIFECYCLE", ctx_of({ "package.json" }, "pnpm"))
eq("tsc deps", runs(f), "pnpm install")
absent("tsc not found makes no ELIFECYCLE finding", "npm-elifecycle", "sh: 1: tsc: not found\n npm ERR! code ELIFECYCLE", ctx_of({ "package.json" }, "pnpm"))
f = expect("local bin", "command-not-found", "sh: 1: vite: not found", ctx_of({ "package.json", "node_modules", "node_modules/.bin/vite" }, "pnpm"))
eq("local bin", runs(f), "pnpm exec vite")
f = expect("windows", "command-not-found", "'cargo' is not recognized as an internal or external command,\noperable program or batch file.")
has_text("windows", f.title, "cargo")
f = expect("spawn enoent", "command-not-found", "Error: spawn git ENOENT\n    at Process.ChildProcess._handle.onexit")
has_text("spawn", runs(f), "sudo apt install git")
f = expect("unknown command", "command-not-found", "bash: foobar: command not found")
has_text("unknown command", f.title, "foobar")
f = expect("pnpm not found", "command-not-found", "bash: pnpm: command not found")
has_text("pnpm corepack", runs(f), "corepack enable")

f = expect("path missing", "path-missing", "bash: ./scripts/seed.sh: No such file or directory")
has_text("path missing", f.title, "./scripts/seed.sh")
f = expect("py file missing", "path-missing", "FileNotFoundError: [Errno 2] No such file or directory: 'data/input.csv'")
has_text("py file missing", f.title, "data/input.csv")
f = expect("package.json missing", "path-missing", "npm ERR! code ENOENT\nnpm ERR! Error: ENOENT: no such file or directory, open '/home/u/package.json'")
has_text("package.json", blob(f), "package.json")
f = expect("py script missing", "path-missing", "python3: can't open file '/app/main.py': [Errno 2] No such file or directory")
has_text("py script missing", f.title, "/app/main.py")
f = expect("go open", "path-missing", "open config.yaml: no such file or directory")
has_text("go open", f.title, "config.yaml")

f = expect("address in use go", "address-in-use", "listen tcp :8080: bind: address already in use")
has_text("address in use go", f.title, "8080")
f = expect("address in use py", "address-in-use", "OSError: [Errno 98] Address already in use")
has_text("address in use py", runs(f), "ss -ltnp")
f = expect("flask port", "address-in-use", "Address already in use\nPort 5000 is in use by another program. Either identify and stop that program, or start the server with a different port.")
has_text("flask port", f.title, "5000")
absent("vite fallback is not an error", "address-in-use", "Port 5173 is in use, trying another one...")

f = expect("jvm oom", "out-of-memory", "Exception in thread \"main\" java.lang.OutOfMemoryError: Java heap space")
has_text("jvm oom", blob(f), "-Xmx2g")
f = expect("cannot allocate", "out-of-memory", "fork: Cannot allocate memory")
has_text("cannot allocate", runs(f), "free -h")
f = expect("go oom", "out-of-memory", "fatal error: runtime: out of memory")

f = expect("segfault", "segfault", "make: *** [Makefile:12: run] Segmentation fault (core dumped)")
has_text("segfault", blob(f), "gdb")
f = expect("segfault native node", "segfault", "Segmentation fault (core dumped)", ctx_of({ "package.json" }, "pnpm"))
has_text("segfault rebuild", runs(f), "pnpm rebuild")

---------------------------------------------------------------------------------------------------------------------
-- Git
---------------------------------------------------------------------------------------------------------------------

f = expect("not a repo", "git-not-repo", "fatal: not a git repository (or any of the parent directories): .git")
has_text("not a repo", runs(f), "git init")

f = expect("conflict", "git-conflict-markers", "Auto-merging src/app.ts\nCONFLICT (content): Merge conflict in src/app.ts\nAutomatic merge failed; fix conflicts and then commit the result.")
has_text("conflict", f.title, "src/app.ts")
has_text("conflict assistant", blob(f), "<leader>Gx")
f = expect("markers", "git-conflict-markers", "src/a.go:5:1: syntax error\n<<<<<<< HEAD\nx := 1\n=======\nx := 2\n>>>>>>> feature")
has_text("markers", runs(f), "git diff --name-only --diff-filter=U")
absent("a lone marker-like text", "git-conflict-markers", "heading <<<<<<< is not at the start of a line\n>>>>>>> nor this")

f = expect("overwritten", "git-overwrite", "error: Your local changes to the following files would be overwritten by merge:\n\tsrc/app.ts\nPlease commit your changes or stash them before you merge.")
has_text("overwritten", runs(f), "git stash push")
has_text("overwritten op", f.title, "merge")
f = expect("untracked overwritten", "git-overwrite", "error: The following untracked working tree files would be overwritten by checkout:\n\tnotes.txt")
has_text("untracked", f.title, "checkout")

---------------------------------------------------------------------------------------------------------------------
-- Cross-cutting rules
---------------------------------------------------------------------------------------------------------------------

-- No known problem
eq("plain text", known.find("Compiling app v0.1.0\nFinished dev [unoptimized] in 2.31s\nerror: something odd failed\n", ctx_of()), {})
eq("empty", known.find("", ctx_of()), {})
eq("nil text", known.find(nil, ctx_of()), {})
eq("nil ctx", #known.find("all good\n", nil), 0)
eq("only a generic word", known.find("Build failed with 3 errors", ctx_of()), {})

-- Evidence: the matched line, trimmed, max 200 chars
f = expect("evidence", "node-port-in-use", "starting...\n   Error: listen EADDRINUSE: address already in use :::3000   \nat Server")
eq("evidence line", f.evidence, "Error: listen EADDRINUSE: address already in use :::3000")
f = expect("evidence cap", "node-port-in-use", "x" .. string.rep("y", 600) .. " EADDRINUSE :::3001 " .. string.rep("z", 600))
ok("evidence <= 200", #f.evidence <= 200)
has_text("evidence window", f.evidence, "EADDRINUSE")

-- Package manager in the commands
for _, pm in ipairs({ "pnpm", "npm", "yarn", "bun" }) do
  f = expect("pm " .. pm, "node-module-missing", "Error: Cannot find module 'left-pad'", ctx_of({}, pm))
  local want = ({ pnpm = "pnpm install", npm = "npm install", yarn = "yarn", bun = "bun install" })[pm]
  eq("install with " .. pm, runs(f), want)
end
f = expect("pm default", "node-module-missing", "Error: Cannot find module 'left-pad'", { has = function() return false end })
eq("default is npm", runs(f), "npm install")

-- Limits and order: at most 6, deduplicated, most specific first
local mix = table.concat({
  "Error: listen EADDRINUSE: address already in use :::3000",
  "Error: Cannot find module 'express'",
  "ModuleNotFoundError: No module named 'requests'",
  "fatal: not a git repository",
  "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?",
  "write /tmp/x: no space left on device",
  "bash: ./run.sh: Permission denied",
  "zsh: command not found: jq",
  "Segmentation fault (core dumped)",
}, "\n")
local list = known.find(mix, ctx_of({ "node_modules" }))
ok("at most 6", #list <= 6)
eq("exactly 6 for the mix", #list, 6)
local seen = {}
for _, x in ipairs(list) do
  ok("dedupe " .. x.id, not seen[x.id])
  seen[x.id] = true
end
local order = known.ids()
local pos = {}
for i, id in ipairs(order) do
  pos[id] = i
end
for i = 2, #list do
  ok("ordered by table position " .. list[i - 1].id .. " < " .. list[i].id, pos[list[i - 1].id] < pos[list[i].id])
end
f = known.find("Error: Cannot find module 'a'\nError: Cannot find module 'b'", ctx_of({ "node_modules" }))
eq("same id twice -> once", #f, 1)
has_text("first occurrence wins", f[1].title, ": a")

-- Shape of every finding the samples above can raise (and the table itself)
local all = known.ids()
ok("about 50 entries", #all >= 30)
local uniq = {}
for _, id in ipairs(all) do
  ok("id is kebab-case: " .. id, id:match("^[a-z0-9]+%-[a-z0-9%-]+$") ~= nil or id:match("^[a-z0-9]+$") ~= nil)
  ok("id is unique: " .. id, not uniq[id])
  uniq[id] = true
end

local shape_text = {
  "Error: Cannot find module 'express'",
  "error TS2307: Cannot find module 'zod' or its corresponding type declarations.",
  "Error: listen EADDRINUSE: address already in use :::3000",
  "ModuleNotFoundError: No module named 'requests'",
  "missing go.sum entry for module providing package github.com/x/y",
  "zsh: command not found: jq",
  "Error: connect ECONNREFUSED 127.0.0.1:5432",
  "Missing required environment variable DATABASE_URL",
  "error: linker `cc` not found",
  "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?",
  "bash: ./run.sh: Permission denied",
  "fatal: not a git repository",
  "npm error code ERESOLVE",
}
local shapes_seen = 0
for _, t in ipairs(shape_text) do
  for _, files in ipairs({ {}, { "node_modules", "package.json", ".nvmrc", "requirements.txt", ".venv", "docker-compose.yml", ".env.example" } }) do
    for _, pm in ipairs({ "npm", "pnpm" }) do
      for _, finding in ipairs(known.find(t, ctx_of(files, pm))) do
        shapes_seen = shapes_seen + 1
        ok(finding.id .. " has 1..3 steps", #finding.steps >= 1 and #finding.steps <= 3)
        ok(finding.id .. " title", type(finding.title) == "string" and finding.title ~= "")
        ok(finding.id .. " cause", type(finding.cause) == "string" and finding.cause ~= "")
        ok(finding.id .. " evidence", type(finding.evidence) == "string" and #finding.evidence > 0 and #finding.evidence <= 200)
        ok(finding.id .. " confidence", finding.confidence == "high" or finding.confidence == "medium")
        for _, s in ipairs(finding.steps) do
          ok(finding.id .. " step kind", s.kind == "command" or s.kind == "manual")
          ok(finding.id .. " step title", type(s.title) == "string" and s.title ~= "")
          if s.kind == "command" then
            ok(finding.id .. " command has run", type(s.run) == "string" and s.run ~= "")
            ok(finding.id .. " command is not destructive", not s.run:find("rm %-rf") and not s.run:find("%-%-force") and not s.run:find("push %-f"))
          else
            ok(finding.id .. " manual has no run", s.run == nil)
          end
        end
      end
    end
  end
end
ok("shape checks ran", shapes_seen > 40)

-- Every id of the table is covered by a sample above (the table grows: a new entry needs its test)
local covered = {}
local function cover(text, files)
  for _, x in ipairs(known.find(text, ctx_of(files or {}, "npm"))) do
    covered[x.id] = true
  end
end
-- the whole run above already exercised them; here the ids are collected once more from compact samples
local compact = {
  "error TS2307: Cannot find module 'zod' or its corresponding type declarations.",
  "Error: Cannot find module 'express'",
  "SyntaxError: Cannot use import statement outside a module",
  "Error: listen EADDRINUSE: address already in use :::3000",
  "npm error code ERESOLVE",
  'error vite@5.0.0: The engine "node" is incompatible with this module. Expected version ">=18". Got "16.20.0"',
  "Error: ENOSPC: System limit for number of file watchers reached, watch '/app'",
  "npm ERR! Error: EACCES: permission denied, mkdir '/usr/lib/node_modules/x'",
  "JavaScript heap out of memory",
  "ModuleNotFoundError: No module named 'requests'",
  "error: externally-managed-environment",
  "zsh: command not found: python",
  "IndentationError: unexpected indent",
  '  File "a.py", line 2\n    x =\n      ^\nSyntaxError: invalid syntax',
  "missing go.sum entry for module providing package github.com/x/y",
  "go: updates to go.mod needed",
  'cgo: C compiler "gcc" not found',
  "build constraints exclude all Go files in /x",
  "package foo/bar is not in std",
  "./a.go:3:2: declared and not used: x",
  "panic: runtime error: index out of range [3] with length 3",
  "error: linker `cc` not found",
  "failed to run custom build command for `openssl-sys v0.9.1`",
  "error[E0432]: unresolved import `foo`",
  "error: no matching package named `foo` found",
  "lock file version 4 was found, but this version of Cargo does not support it",
  "thread 'main' panicked at src/main.rs:1:1:",
  "JAVA_HOME is not set",
  "Unsupported class file major version 65",
  "Could not resolve com.a:b:1.0.",
  'Could not find a file named "pubspec.yaml" in "/x".',
  "Because a depends on b, version solving failed.",
  "Some Android licenses not accepted.",
  "CocoaPods not installed.",
  "permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock",
  "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?",
  "Bind for 0.0.0.0:5432 failed: port is already allocated",
  "no space left on device",
  "Error: connect ECONNREFUSED 127.0.0.1:5432",
  "open .env: no such file or directory",
  "Missing required environment variable DATABASE_URL",
  "bash: ./a.sh: /bin/bash^M: bad interpreter: No such file or directory",
  "bash: ./a.sh: Permission denied",
  "PermissionError: [Errno 13] Permission denied: '/var/x'",
  "bash: foobar: command not found",
  "bash: ./a/b.sh: No such file or directory",
  "listen tcp :8080: bind: address already in use",
  "java.lang.OutOfMemoryError: Java heap space",
  "Segmentation fault (core dumped)",
  "fatal: not a git repository",
  "CONFLICT (content): Merge conflict in a.txt",
  "error: Your local changes to the following files would be overwritten by merge:",
  "npm ERR! code ELIFECYCLE",
}
for _, t in ipairs(compact) do
  cover(t, { "node_modules" })
end
for _, id in ipairs(all) do
  ok("a sample covers " .. id, covered[id] == true)
end

-- Speed: 200 KB of noise (near-misses of many signatures) stays fast; the same noise ending in one signature finds it
local noise_lines = {
  "npm WARN deprecated foo@1.0.0: this package is no longer supported",
  "info: compiling module (123/456) src/app/foo.ts could not be found in cache, rebuilding",
  "warning: connection established to the server, no refused packets, port 8080 is fine",
  "the module was resolved, nothing is missing, address book updated, permission granted",
  "error: something failed while formatting the output of the build, will retry",
  "cannot find the time to write more noise here, command line parsing finished",
  "no such luck with the cache today; docker layers reused; git is clean; java is fine",
}
local parts, size, i = {}, 0, 1
while size < 200 * 1024 do
  local l = noise_lines[(i - 1) % #noise_lines + 1] .. "\n"
  parts[#parts + 1] = l
  size = size + #l
  i = i + 1
end
local noise = table.concat(parts)
local t0 = vim.uv.hrtime()
local res = known.find(noise, ctx_of())
local ms = (vim.uv.hrtime() - t0) / 1e6
eq("noise finds nothing", res, {})
ok("200 KB of noise is fast (" .. math.floor(ms) .. " ms)", ms < 200)

-- A single 200 KB line (no newline) must not be quadratic either
local oneline = string.rep("error: cannot find the thing; connection reset; no such luck; permission ", 3000)
t0 = vim.uv.hrtime()
res = known.find(oneline, ctx_of())
ms = (vim.uv.hrtime() - t0) / 1e6
ok("one long line is fast (" .. math.floor(ms) .. " ms)", ms < 200)

t0 = vim.uv.hrtime()
res = known.find(noise .. "Error: listen EADDRINUSE: address already in use :::4321\n", ctx_of())
ms = (vim.uv.hrtime() - t0) / 1e6
ok("signature after the noise is found", get(res, "node-port-in-use") ~= nil)
ok("... and fast (" .. math.floor(ms) .. " ms)", ms < 200)

-- Worst case for the matchers: every signature's first words repeated many times
local near = {}
for _, w in ipairs({ "cannot find module", "connection refused", "permission denied", "command not found", "no such file or directory", "econnrefused", "eaddrinuse", "is not set", "unresolved import", "version solving" }) do
  near[#near + 1] = string.rep("x " .. w .. " ", 300) .. "\n"
end
local nearly = string.rep(table.concat(near), 6)
t0 = vim.uv.hrtime()
known.find(nearly, ctx_of())
ms = (vim.uv.hrtime() - t0) / 1e6
ok("near-signatures stay fast (" .. math.floor(ms) .. " ms, " .. #nearly .. " bytes)", ms < 200)

print(string.format("%d checks, %d failed", total, fails))
if fails == 0 then
  print("ALL OK")
end
vim.cmd("qa!")
