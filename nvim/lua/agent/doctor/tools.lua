-- ── What the model may look at while it diagnoses ────────────────────────────
-- When the evidence is not enough the model asks for more: a file's lines, a search, a folder, or a read-only command. This is
-- all it can ask for. It never runs a shell: a command is split into words, checked against an allowlist of read-only
-- diagnostics (versions, package lists, git history, docker state, who listens on a port) and run directly; what it prints
-- is redacted and cut. Files that hold secrets are never readable. Every refusal is written back to the model as the result, so
-- it adapts instead of failing. `parse_run` and `readable` are pure.
local evidence = require "agent.doctor.evidence"
local settings = require("core.settings").agent.doctor

local M = {}

M.DESCRIPTION = [[You may ask for more evidence with "need": [{"tool":"read","path":"src/a.ts","from":1,"to":80}, {"tool":"search","pattern":"exact text"}, {"tool":"list","path":"src"}, {"tool":"run","cmd":"node -v"}]. read: lines of a project file (max 120, never secrets). search: an exact string in the project (30 hits). list: a folder. run: ONE read-only diagnostic command (versions, package lists, git status/log/diff, docker ps/logs --tail, which, lsof -i :PORT, df, free); no pipes, no redirects, nothing that changes anything.]]

--- Files whose content is a secret or credentials
---@param rel string relative path
---@return boolean
local function secret_path(rel)
  local name = rel:match "([^/]+)$" or rel
  local low = name:lower()
  if low:match "^%.env" and not (low:match "%.example$" or low:match "%.sample$" or low:match "%.template$") then
    return true
  end
  for _, pat in ipairs {
    "%.pem$",
    "%.key$",
    "%.p12$",
    "%.pfx$",
    "^id_[%w_]+$",
    "^credentials",
    "^%.npmrc$",
    "^%.pypirc$",
    "^%.netrc$",
    "^%.git%-credentials$",
    "^secrets?%.",
    "%.keystore$",
    "%.jks$",
  } do
    if low:match(pat) then
      return true
    end
  end
  for _, dir in ipairs { "%.ssh/", "%.aws/", "%.gnupg/", "%.git/" } do
    if ("/" .. rel .. "/"):match("/" .. dir) then
      return true
    end
  end
  return false
end

--- A project path the model may read: inside the root, not a secret. Returns the absolute path or nil and why
---@param root string
---@param rel string
---@return string? abs, string? why
function M.readable(root, rel)
  if type(rel) ~= "string" or rel == "" then
    return nil, "no path given"
  end
  local abs = vim.fs.normalize(rel:match "^/" and rel or (root .. "/" .. rel))
  local base = vim.fs.normalize(root)
  if abs ~= base and abs:sub(1, #base + 1) ~= base .. "/" then
    return nil, "that path is outside the project"
  end
  local inner = abs:sub(#base + 2)
  if secret_path(inner) then
    return nil, "that file may hold secrets: ask the user to paste the relevant, safe part"
  end
  return abs
end

-- command → what may follow it. `any` = any further words that are not flags in `deny`; a list = the allowed first words
local RUN = {
  go = { sub = { version = true, env = true, list = true, mod = { graph = true, why = true, verify = true } } },
  node = { flags = { ["-v"] = true, ["--version"] = true } },
  npm = { flags = { ["-v"] = true }, sub = { ls = true, list = true, view = true, config = { get = true }, outdated = true } },
  pnpm = { flags = { ["-v"] = true }, sub = { ls = true, list = true, why = true, outdated = true } },
  yarn = { flags = { ["-v"] = true }, sub = { list = true, why = true } },
  bun = { flags = { ["-v"] = true }, sub = { pm = { ls = true } } },
  python3 = { flags = { ["--version"] = true, ["-V"] = true }, sub = { ["-m"] = { pip = { list = true, show = true, check = true } } } },
  python = { flags = { ["--version"] = true, ["-V"] = true }, sub = { ["-m"] = { pip = { list = true, show = true, check = true } } } },
  pip = { sub = { list = true, show = true, check = true } },
  pip3 = { sub = { list = true, show = true, check = true } },
  cargo = { flags = { ["--version"] = true, ["-V"] = true }, sub = { tree = true } },
  rustc = { flags = { ["-V"] = true, ["--version"] = true } },
  java = { flags = { ["-version"] = true, ["--version"] = true } },
  javac = { flags = { ["-version"] = true } },
  dart = { flags = { ["--version"] = true } },
  flutter = { flags = { ["--version"] = true }, sub = { doctor = true } },
  ruby = { flags = { ["-v"] = true } },
  php = { flags = { ["-v"] = true } },
  git = {
    sub = {
      status = true,
      log = true,
      diff = true,
      show = true,
      branch = true,
      remote = true,
      ["rev-parse"] = true,
      ["ls-files"] = true,
      blame = true,
      stash = { list = true },
    },
    deny = { "^%-c$", "^%-%-output", "^%-%-ext%-diff", "^%-%-exec", "^%-%-upload%-pack", "^%-%-textconv" },
  },
  docker = { sub = { ps = true, info = true, images = true, logs = true, compose = { ps = true, logs = true, config = true } } },
  which = { any = true },
  uname = { any = true },
  df = { any = true },
  free = { any = true },
  pwd = { any = true },
  ls = { any = true, path = true },
  lsof = { sub = { ["-i"] = true }, any = true },
  ss = { any = true },
}

--- A command line turned into argv if it is on the allowlist; nil and why otherwise (pure)
---@param cmd string
---@return string[]? argv, string? why
function M.parse_run(cmd)
  if type(cmd) ~= "string" or vim.trim(cmd) == "" then
    return nil, "no command given"
  end
  if cmd:find "[;&|<>$`\\()\n]" then
    return nil, "no pipes, redirects, substitutions or chained commands: one plain command"
  end
  local argv = vim.split(vim.trim(cmd), "%s+", { trimempty = true })
  local rule = RUN[argv[1]]
  if not rule then
    return nil, ("`%s` is not a read-only diagnostic command I run"):format(argv[1])
  end
  for i = 2, #argv do
    for _, pat in ipairs(rule.deny or {}) do
      if argv[i]:match(pat) then
        return nil, "that flag is not allowed"
      end
    end
  end
  if rule.any then
    for i = 2, #argv do
      if rule.path and (argv[i]:find("..", 1, true) or argv[i]:match "^[/~]") then
        return nil, "paths stay inside the project"
      end
    end
    if argv[1] == "lsof" and argv[2] ~= "-i" then
      return nil, "only `lsof -i :PORT` (who listens on a port)"
    end
    return argv
  end
  if #argv == 1 then
    return nil, ("`%s` needs a subcommand or a version flag"):format(argv[1])
  end
  if rule.flags and rule.flags[argv[2]] and #argv == 2 then
    return argv
  end
  local node = rule.sub
  local i = 2
  while type(node) == "table" and argv[i] do
    local nxt = node[argv[i]]
    if nxt == nil then
      return nil, ("`%s %s` is not allowed"):format(argv[1], argv[i])
    end
    node = nxt
    i = i + 1
    if nxt == true then
      break
    end
  end
  if node ~= true and type(node) == "table" and not rule.any then
    return nil, ("`%s` needs one of: %s"):format(table.concat(vim.list_slice(argv, 1, i - 1), " "), table.concat(vim.tbl_keys(node), ", "))
  end
  -- logs are bounded: a tail or nothing (a service's whole history is not evidence)
  if argv[1] == "docker" and vim.tbl_contains(argv, "logs") and not vim.tbl_contains(argv, "--tail") then
    vim.list_extend(argv, { "--tail", "200" })
  end
  if argv[1] == "npm" and argv[2] == "config" then
    local key = (argv[4] or ""):lower()
    for _, bad in ipairs { "token", "auth", "pass", "cert", "key", "secret" } do
      if key:find(bad, 1, true) then
        return nil, "that setting may hold a credential"
      end
    end
  end
  return argv
end

---@param text string
---@return string
local function clip(text)
  text = evidence.redact(evidence.clean(text))
  local max = settings.tool_output_chars
  return #text > max and (text:sub(1, max) .. "\n[… cut]") or text
end

---@param call table
---@param root string
---@param cb fun(text: string)
local function read(call, root, cb)
  local abs, why = M.readable(root, call.path)
  if not abs then
    return cb("refused: " .. why)
  end
  local ok, lines = pcall(vim.fn.readfile, abs)
  if not ok then
    return cb("refused: cannot read " .. tostring(call.path))
  end
  if table.concat(vim.list_slice(lines, 1, 20), "\n"):find "%z" then
    return cb "refused: that is a binary file"
  end
  local from = math.max(1, tonumber(call.from) or 1)
  local to = math.min(#lines, tonumber(call.to) or (from + 119), from + 119)
  local out = {}
  for i = from, to do
    out[#out + 1] = ("%4d  %s"):format(i, lines[i])
  end
  cb(clip(("%s lines %d-%d of %d:\n%s"):format(call.path, from, to, #lines, table.concat(out, "\n"))))
end

---@param call table
---@param root string
---@param cb fun(text: string)
local function search(call, root, cb)
  if type(call.pattern) ~= "string" or call.pattern == "" then
    return cb "refused: no pattern given"
  end
  if vim.fn.executable "rg" ~= 1 then
    return cb "refused: ripgrep (rg) is not installed here"
  end
  local cmd = {
    "rg",
    "--line-number",
    "--no-heading",
    "--max-count",
    "5",
    "--max-columns",
    "200",
    "-F",
    "--glob",
    "!.git",
    "--glob",
    "!node_modules",
    "--glob",
    "!.env*",
    "--glob",
    "!*.pem",
    "--glob",
    "!*.key",
    "--glob",
    "!*lock*",
    "--",
    call.pattern,
    root,
  }
  vim.system(cmd, { text = true, timeout = 10000 }, function(res)
    vim.schedule(function()
      local lines = vim.split(vim.trim(res.stdout or ""), "\n", { plain = true })
      if #lines == 1 and lines[1] == "" then
        return cb("no match for `" .. call.pattern .. "`")
      end
      local out = {}
      for i = 1, math.min(#lines, 30) do
        out[#out + 1] = (lines[i]:gsub("^" .. vim.pesc(root) .. "/", ""))
      end
      cb(clip(table.concat(out, "\n")))
    end)
  end)
end

---@param call table
---@param root string
---@param cb fun(text: string)
local function list(call, root, cb)
  local abs, why = M.readable(root, (call.path == nil or call.path == "" or call.path == ".") and root or call.path)
  if not abs then
    return cb("refused: " .. why)
  end
  local out = {}
  for name, kind in vim.fs.dir(abs) do
    if name ~= ".git" and not secret_path(name) then
      out[#out + 1] = kind == "directory" and (name .. "/") or name
    end
  end
  table.sort(out)
  cb(clip(#out == 0 and "(empty or not a folder)" or table.concat(vim.list_slice(out, 1, 80), "\n")))
end

---@param call table
---@param root string
---@param cb fun(text: string)
local function run(call, root, cb)
  local argv, why = M.parse_run(call.cmd)
  if not argv then
    return cb("refused: " .. why)
  end
  if vim.fn.executable(argv[1]) ~= 1 then
    return cb(("`%s` is not installed here"):format(argv[1]))
  end
  vim.system(argv, { cwd = root, text = true, timeout = 30000 }, function(res)
    vim.schedule(function()
      local text = vim.trim((res.stdout or "") .. "\n" .. (res.stderr or ""))
      cb(clip(("$ %s (exit %d)\n%s"):format(table.concat(argv, " "), res.code, text)))
    end)
  end)
end

local TOOLS = { read = read, search = search, list = list, run = run }

--- Runs what the model asked for; `cb(text)` always (a refusal is a text too)
---@param call table
---@param root string
---@param cb fun(text: string)
function M.call(call, root, cb)
  local tool = type(call) == "table" and TOOLS[call.tool]
  if not tool then
    return cb("refused: unknown tool (read, search, list, run)")
  end
  local ok, err = pcall(tool, call, root, cb)
  if not ok then
    cb("refused: " .. tostring(err))
  end
end

return M
