-- ── git para el panel de commit ──────────────────────────────────────────────
-- Lecturas síncronas y baratas (status, numstat, rama) y las acciones que modifican (preparar, quitar de lo
-- preparado, commitear). Sin UI: el panel solo pinta lo que esto devuelve.
local M = {}

---@param args string[]
---@param root string
---@param stdin string?
---@return string stdout, integer code, string stderr
function M.run(args, root, stdin)
  local res = vim.system(vim.list_extend({ "git" }, args), { cwd = root, text = true, stdin = stdin }):wait()
  return res.stdout or "", res.code, res.stderr or ""
end

---@param args string[]
---@param root string
---@return string
local function out(args, root)
  local stdout, code = M.run(args, root)
  return code == 0 and vim.trim(stdout) or ""
end

--- Raíz del repo del buffer actual (o del cwd si no tiene archivo)
---@return string?
function M.root()
  local name = vim.api.nvim_buf_get_name(0)
  return vim.fs.root(name ~= "" and 0 or vim.uv.cwd(), ".git")
end

---@class CommitBranch
---@field name string
---@field upstream string?
---@field ahead integer
---@field behind integer

---@param root string
---@return CommitBranch
function M.branch(root)
  local info = { name = out({ "rev-parse", "--abbrev-ref", "HEAD" }, root), ahead = 0, behind = 0 }
  if info.name == "" then
    info.name = "(no commits yet)"
  end
  local upstream = out({ "rev-parse", "--abbrev-ref", "@{u}" }, root)
  if upstream ~= "" then
    info.upstream = upstream
    local counts = out({ "rev-list", "--left-right", "--count", "@{u}...HEAD" }, root)
    local behind, ahead = counts:match "(%d+)%s+(%d+)"
    info.behind, info.ahead = tonumber(behind) or 0, tonumber(ahead) or 0
  end
  return info
end

---@param root string
---@return boolean
function M.has_head(root)
  local _, code = M.run({ "rev-parse", "--verify", "-q", "HEAD" }, root)
  return code == 0
end

--- adds/dels por ruta de `git diff --numstat -z` (sin detección de renombrados: una ruta, un número)
---@param root string
---@param cached boolean
---@return table<string, { adds: integer?, dels: integer? }>
local function numstat(root, cached)
  local args = { "diff", "--numstat", "-z", "--no-renames" }
  if cached then
    table.insert(args, 2, "--cached")
  end
  local stdout = M.run(args, root)
  local stats = {}
  for rec in stdout:gmatch "[^%z]+" do
    local adds, dels, path = rec:match "^(%S+)\t(%S+)\t(.+)$"
    if path then -- binario: "-" "-"
      stats[path] = { adds = tonumber(adds), dels = tonumber(dels) }
    end
  end
  return stats
end

---@class CommitEntry
---@field path string
---@field letter string         M A D R C ? U
---@field staged boolean        ¿va en el commit?
---@field partial boolean       preparado, pero con más cambios sin preparar
---@field untracked boolean
---@field adds integer?
---@field dels integer?

--- Estado del árbol: primero lo preparado (lo que se commitea), luego lo modificado sin preparar, luego lo nuevo
---@param root string
---@return CommitEntry[]
function M.status(root)
  local stdout = M.run({ "status", "--porcelain=v1", "-z" }, root)
  local cached, worktree = numstat(root, true), numstat(root, false)
  local staged, unstaged, untracked = {}, {}, {}
  local fields = vim.split(stdout, "\0", { plain = true })
  local i = 1
  while i <= #fields do
    local rec = fields[i]
    i = i + 1
    if #rec >= 4 then
      local x, y, path = rec:sub(1, 1), rec:sub(2, 2), rec:sub(4)
      if x == "R" or x == "C" then
        i = i + 1 -- el siguiente campo es la ruta original
      end
      local entry = { path = path, letter = "M", staged = false, partial = false, untracked = false }
      if x == "?" then
        entry.letter, entry.untracked = "?", true
        untracked[#untracked + 1] = entry
      elseif x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then
        entry.letter = "U"
        unstaged[#unstaged + 1] = entry
      elseif x ~= " " then
        entry.letter, entry.staged, entry.partial = x, true, y ~= " "
        local s = cached[path] or {}
        entry.adds, entry.dels = s.adds, s.dels
        staged[#staged + 1] = entry
      else
        entry.letter = y
        local s = worktree[path] or {}
        entry.adds, entry.dels = s.adds, s.dels
        unstaged[#unstaged + 1] = entry
      end
    end
  end
  local list = staged
  vim.list_extend(list, unstaged)
  vim.list_extend(list, untracked)
  return list
end

---@param root string
---@param paths string[]
---@return boolean ok, string err
function M.stage(root, paths)
  local _, code, err = M.run(vim.list_extend({ "add", "-A", "--" }, paths), root)
  return code == 0, err
end

---@param root string
---@param paths string[]
---@return boolean ok, string err
function M.unstage(root, paths)
  local args = M.has_head(root) and { "restore", "--staged", "--" } or { "rm", "--cached", "-r", "-q", "--" }
  local _, code, err = M.run(vim.list_extend(args, paths), root)
  return code == 0, err
end

--- Diff de una fila (lo preparado, lo no preparado, o el archivo nuevo entero)
---@param root string
---@param entry CommitEntry
---@return string[]
function M.diff(root, entry)
  local args
  if entry.untracked then
    args = { "diff", "--no-index", "--no-color", "--", "/dev/null", entry.path }
  elseif entry.staged then
    args = { "diff", "--cached", "--no-color", "--", entry.path }
  else
    args = { "diff", "--no-color", "--", entry.path }
  end
  local stdout = M.run(args, root) -- --no-index sale con código 1 cuando hay diferencias: es normal
  local lines = vim.split(stdout, "\n", { plain = true })
  return stdout == "" and { "(no textual changes)" } or lines
end

---@param root string
---@param n integer
---@return string
function M.recent_subjects(root, n)
  return out({ "log", "-n", tostring(n), "--format=%s" }, root)
end

---@param root string
---@return string stat  `git diff --cached --stat`
function M.staged_stat(root)
  return out({ "diff", "--cached", "--stat" }, root)
end

--- Diff preparado sin lockfiles, recortado a `max` caracteres
---@param root string
---@param max integer
---@return string diff, integer total_chars, boolean truncated
function M.staged_diff(root, max)
  local diff = out({ "diff", "--cached", "-U2", "--no-color", "--", ".", ":(exclude)*lock*", ":(exclude)*.sum" }, root)
  local total = #diff
  if total > max then
    return diff:sub(1, max) .. "\n[diff truncated]", total, true
  end
  return diff, total, false
end

---@param root string
---@return { hash: string, subject: string, message: string }?
function M.head(root)
  local msg, code = M.run({ "log", "-1", "--format=%h%x00%B" }, root)
  if code ~= 0 then
    return nil
  end
  local hash, body = msg:match "^([^%z]+)%z(.*)$"
  body = vim.trim(body or "")
  return hash and { hash = hash, subject = vim.split(body, "\n", { plain = true })[1], message = body } or nil
end

--- ¿HEAD ya está en algún remoto? (reescribirlo rompería el historial de otros)
---@param root string
---@return boolean
function M.head_on_remote(root)
  return out({ "branch", "-r", "--contains", "HEAD" }, root) ~= ""
end

--- Commitea lo preparado. `cb(ok, hash_o_error)`
---@param root string
---@param msg string
---@param amend boolean
---@param cb fun(ok: boolean, info: string)
---@return vim.SystemObj
function M.commit(root, msg, amend, cb)
  local cmd = { "git", "commit", "-F", "-" }
  if amend then
    table.insert(cmd, 3, "--amend")
  end
  return vim.system(cmd, { cwd = root, text = true, stdin = msg .. "\n" }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        return cb(false, vim.trim((res.stderr or "") .. (res.stdout or "")))
      end
      cb(true, out({ "rev-parse", "--short", "HEAD" }, root))
    end)
  end)
end

return M
