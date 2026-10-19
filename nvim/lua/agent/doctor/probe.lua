-- ── Probes: what the project and the machine look like ───────────────────────
-- Free checks (no model) that explain many failures before anything is run: dependencies not installed, a lockfile older than
-- its manifest, `.env` missing keys its example has, the toolchain version the project asks for against the one installed,
-- a merge in progress. Plus the read-only commands that tell the model about the machine (versions, what changed in git).
-- The checks are pure over `ctx` (has / read / mtime), so they are tested without a project; `versions` and `changes` run git
-- and the toolchains, asynchronously, each with a short timeout.
local M = {}

---@class DoctorCtx
---@field root string
---@field has fun(rel: string): boolean
---@field read fun(rel: string): string?
---@field mtime fun(rel: string): integer?

---@param root string
---@return DoctorCtx
function M.ctx(root)
  local function abs(rel)
    return root .. "/" .. rel
  end
  return {
    root = root,
    has = function(rel)
      return vim.uv.fs_stat(abs(rel)) ~= nil
    end,
    read = function(rel)
      local ok, lines = pcall(vim.fn.readfile, abs(rel))
      return ok and table.concat(lines, "\n") or nil
    end,
    mtime = function(rel)
      local st = vim.uv.fs_stat(abs(rel))
      return st and st.mtime.sec or nil
    end,
  }
end

--- The package manager a JS project uses (its lockfile, then `packageManager`), nil when it is not a JS project
---@param ctx DoctorCtx
---@return "pnpm"|"npm"|"yarn"|"bun"?
function M.package_manager(ctx)
  if not ctx.has "package.json" then
    return nil
  end
  if ctx.has "pnpm-lock.yaml" then
    return "pnpm"
  elseif ctx.has "yarn.lock" then
    return "yarn"
  elseif ctx.has "bun.lockb" or ctx.has "bun.lock" then
    return "bun"
  elseif ctx.has "package-lock.json" then
    return "npm"
  end
  local pkg = ctx.read "package.json" or ""
  local declared = pkg:match '"packageManager"%s*:%s*"(%a+)@'
  return declared == "pnpm" and "pnpm" or declared == "yarn" and "yarn" or declared == "bun" and "bun" or "npm"
end

---@param pm string?
---@return string
local function install_cmd(pm)
  return (pm == "yarn" and "yarn") or (pm == "pnpm" and "pnpm install") or (pm == "bun" and "bun install") or "npm install"
end

--- The keys of a dotenv text (comments and blanks skipped)
---@param text string
---@return string[]
local function env_keys(text)
  local keys = {}
  for line in (text .. "\n"):gmatch "(.-)\n" do
    local key = line:match "^%s*export%s+([%w_]+)%s*=" or line:match "^%s*([%w_]+)%s*="
    if key then
      keys[#keys + 1] = key
    end
  end
  return keys
end

---@param id string
---@param title string
---@param cause string
---@param steps DoctorStep[]
---@return DoctorFinding
local function finding(id, title, cause, steps)
  return { id = id, title = title, cause = cause, evidence = "", steps = steps, confidence = "high" }
end

--- The findings no output is needed for (pure over ctx)
---@param ctx DoctorCtx
---@return DoctorFinding[]
function M.checks(ctx)
  local out = {}
  local pm = M.package_manager(ctx)
  if pm then
    if not ctx.has "node_modules" and not ctx.has ".pnp.cjs" then
      out[#out + 1] = finding(
        "deps-not-installed",
        "The JavaScript dependencies are not installed",
        "package.json is there but node_modules is not: nothing that imports a package can run or build.",
        { { kind = "command", title = "Install the dependencies", run = install_cmd(pm) } }
      )
    else
      local lock = (pm == "pnpm" and "pnpm-lock.yaml")
        or (pm == "yarn" and "yarn.lock")
        or (pm == "bun" and (ctx.has "bun.lock" and "bun.lock" or "bun.lockb"))
        or "package-lock.json"
      local manifest, locked = ctx.mtime "package.json", ctx.mtime(lock)
      if manifest and locked and manifest > locked + 2 then
        out[#out + 1] = finding(
          "lockfile-older",
          "package.json changed after the lockfile",
          "A dependency was added or changed without installing: node_modules may not match what the code imports.",
          { { kind = "command", title = "Install what package.json says", run = install_cmd(pm) } }
        )
      end
    end
  end
  if ctx.has ".env.example" or ctx.has ".env.sample" then
    local example = ctx.read(ctx.has ".env.example" and ".env.example" or ".env.sample") or ""
    if not ctx.has ".env" then
      out[#out + 1] = finding(
        "env-missing",
        "There is no .env file",
        "The project ships an example of the variables it reads, and no .env exists: anything that needs a variable starts without it.",
        { { kind = "manual", title = "Copy the example and fill in the values", note = "cp .env.example .env, then set each value yourself" } }
      )
    else
      local have = {}
      for _, k in ipairs(env_keys(ctx.read ".env" or "")) do
        have[k] = true
      end
      local missing = vim.tbl_filter(function(k)
        return not have[k]
      end, env_keys(example))
      if #missing > 0 then
        out[#out + 1] = finding(
          "env-keys-missing",
          ("%s missing from .env"):format(table.concat(vim.list_slice(missing, 1, 6), ", ")),
          "The example file lists variables your .env does not set" .. (#missing > 6 and (" (" .. #missing .. " in all)") or "") .. ".",
          { { kind = "manual", title = "Add the missing variables to .env", note = "values are yours: the agent never invents them" } }
        )
      end
    end
  end
  if ctx.has ".git/MERGE_HEAD" or ctx.has ".git/rebase-merge" or ctx.has ".git/rebase-apply" then
    out[#out + 1] = finding(
      "git-operation",
      "A merge or rebase is in progress",
      "Files can hold conflict markers that no compiler accepts, and the tree is half-way between two histories.",
      { { kind = "manual", title = "Resolve the conflicts", note = "<leader>Gxf lists the files, <leader>Gxt and <leader>Gxr resolve them" } }
    )
  end
  return out
end

---@param text string?
---@return integer?
local function major(text)
  return tonumber((text or ""):match "v?(%d+)")
end

--- The toolchain findings once `versions` is known (pure): what the project asks for against what is installed
---@param ctx DoctorCtx
---@param versions table<string, string>
---@return DoctorFinding[]
function M.version_checks(ctx, versions)
  local out = {}
  local want_node = major(ctx.read ".nvmrc" or ctx.read ".node-version")
  local have_node = major(versions.node)
  if want_node and have_node and want_node ~= have_node then
    out[#out + 1] = finding(
      "node-version",
      ("The project wants Node %d and %d is installed"):format(want_node, have_node),
      ".nvmrc (or .node-version) pins a major version that is not the one running.",
      { { kind = "command", title = "Switch to the pinned version", run = "nvm use" } }
    )
  end
  local go_mod = ctx.read "go.mod" or ""
  local want_go = go_mod:match "\ngo%s+(%d+%.%d+)" or go_mod:match "^go%s+(%d+%.%d+)"
  local have_go = (versions.go or ""):match "go(%d+%.%d+)"
  if want_go and have_go then
    local function num(v)
      local a, b = v:match "(%d+)%.(%d+)"
      return tonumber(a) * 1000 + tonumber(b)
    end
    if num(want_go) > num(have_go) then
      out[#out + 1] = finding(
        "go-version",
        ("go.mod needs Go %s and %s is installed"):format(want_go, have_go),
        "The module asks for a newer toolchain than the one on this machine.",
        { { kind = "manual", title = "Install a newer Go", note = "or let `GOTOOLCHAIN=auto` download it (go 1.21+)" } }
      )
    end
  end
  if versions.docker_error then
    out[#out + 1] = finding(
      "docker-down",
      "The Docker daemon is not reachable",
      "A compose file is in the project and `docker info` fails: services the app talks to are not running.",
      { { kind = "manual", title = "Start Docker", note = versions.docker_error:sub(1, 160) } }
    )
  end
  return out
end

--- The toolchains this project uses, from its marker files
---@param ctx DoctorCtx
---@return { name: string, cmd: string[] }[]
function M.tools(ctx)
  local list = {}
  local function add(name, ...)
    list[#list + 1] = { name = name, cmd = { ... } }
  end
  if ctx.has "package.json" then
    add("node", "node", "-v")
    local pm = M.package_manager(ctx)
    if pm and pm ~= "npm" then
      add(pm, pm, "-v")
    else
      add("npm", "npm", "-v")
    end
  end
  if ctx.has "go.mod" then
    add("go", "go", "version")
  end
  if ctx.has "Cargo.toml" then
    add("rustc", "rustc", "-V")
    add("cargo", "cargo", "-V")
  end
  if ctx.has "pyproject.toml" or ctx.has "requirements.txt" or ctx.has "setup.py" then
    add("python", "python3", "--version")
  end
  if ctx.has "pom.xml" or ctx.has "build.gradle" or ctx.has "build.gradle.kts" then
    add("java", "java", "-version")
  end
  if ctx.has "pubspec.yaml" then
    add("dart", "dart", "--version")
  end
  if ctx.has "Gemfile" then
    add("ruby", "ruby", "-v")
  end
  if ctx.has "composer.json" then
    add("php", "php", "-v")
  end
  if ctx.has "docker-compose.yml" or ctx.has "docker-compose.yaml" or ctx.has "compose.yaml" or ctx.has "compose.yml" or ctx.has "Dockerfile" then
    add("docker", "docker", "info", "--format", "{{.ServerVersion}}")
  end
  return list
end

--- Runs a read-only command with a short timeout; `cb(stdout, stderr, code)`
---@param cmd string[]
---@param cwd string
---@param cb fun(out: string, err: string, code: integer)
local function exec(cmd, cwd, cb)
  if vim.fn.executable(cmd[1]) ~= 1 then
    return cb("", cmd[1] .. ": not installed", 127)
  end
  local ok = pcall(vim.system, cmd, { cwd = cwd, text = true, timeout = 4000 }, function(res)
    vim.schedule(function()
      cb(vim.trim(res.stdout or ""), vim.trim(res.stderr or ""), res.code)
    end)
  end)
  if not ok then
    cb("", "could not start", 1)
  end
end

--- The versions of the project's toolchains, all at once. `cb(versions)` with name → first line (`docker_error` when the daemon is down)
---@param ctx DoctorCtx
---@param cb fun(versions: table<string, string>)
function M.versions(ctx, cb)
  local tools = M.tools(ctx)
  local out, left = {}, #tools
  if left == 0 then
    return cb(out)
  end
  for _, t in ipairs(tools) do
    exec(t.cmd, ctx.root, function(stdout, stderr, code)
      local text = (stdout ~= "" and stdout or stderr):match "[^\n]+" or ""
      if t.name == "docker" then
        if code ~= 0 then
          out.docker_error = (stderr ~= "" and stderr or "docker info failed"):match "[^\n]+"
        else
          out.docker = stdout
        end
      elseif code == 127 then
        out[t.name .. "_missing"] = text
      else
        out[t.name] = text
      end
      left = left - 1
      if left == 0 then
        cb(out)
      end
    end)
  end
end

--- What changed in git lately (status, last commits, the diff size): "it worked before" starts here
---@param ctx DoctorCtx
---@param cb fun(text: string)
function M.changes(ctx, cb)
  local parts = {
    { "status", "--short", "-b" },
    { "log", "-5", "--format=%h %s (%ar)" },
    { "diff", "--stat", "HEAD" },
  }
  local outs, left = {}, #parts
  for i, args in ipairs(parts) do
    local cmd = { "git", "-C", ctx.root }
    vim.list_extend(cmd, args)
    exec(cmd, ctx.root, function(stdout)
      outs[i] = stdout
      left = left - 1
      if left == 0 then
        local text = {}
        if outs[1] ~= "" then
          text[#text + 1] = "git status:\n" .. table.concat(vim.list_slice(vim.split(outs[1], "\n"), 1, 15), "\n")
        end
        if outs[2] ~= "" then
          text[#text + 1] = "last commits:\n" .. outs[2]
        end
        if outs[3] ~= "" then
          text[#text + 1] = "uncommitted changes:\n" .. table.concat(vim.list_slice(vim.split(outs[3], "\n"), 1, 15), "\n")
        end
        cb(table.concat(text, "\n\n"))
      end
    end)
  end
end

return M
