-- ── git for the commit panel ─────────────────────────────────────────────────
-- Cheap synchronous reads (status, numstat, branch) and the actions that modify (stage, unstage,
-- commit). No UI: the panel only paints what this returns.
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

--- Repo root of the current buffer (or of the cwd if it has no file)
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
---@return string
function M.branch_name(root)
  return out({ "rev-parse", "--abbrev-ref", "HEAD" }, root)
end

---@param root string
---@return boolean
function M.has_head(root)
  local _, code = M.run({ "rev-parse", "--verify", "-q", "HEAD" }, root)
  return code == 0
end

--- adds/dels per path from `git diff --numstat -z` (no rename detection: one path, one number)
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
    if path then -- binary: "-" "-"
      stats[path] = { adds = tonumber(adds), dels = tonumber(dels) }
    end
  end
  return stats
end

---@class CommitEntry
---@field path string
---@field letter string         M A D R C ? U
---@field staged boolean        goes in the commit?
---@field partial boolean       staged, but with more unstaged changes
---@field untracked boolean
---@field adds integer?
---@field dels integer?

--- Tree status: first what is staged (what gets committed), then modified but unstaged, then new
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
        i = i + 1 -- the next field is the original path
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

--- Diff of one row (the staged part, the unstaged part, or the whole new file)
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
  local stdout = M.run(args, root) -- --no-index exits with code 1 when there are differences: that is normal
  local lines = vim.split(stdout, "\n", { plain = true })
  return stdout == "" and { "(no textual changes)" } or lines
end

---@param root string
---@param n integer
---@return string
function M.recent_subjects(root, n)
  return out({ "log", "-n", tostring(n), "--format=%s" }, root)
end

-- Files that add nothing to the message (they are listed, but their diff is not sent)
local NOISE = { "lock", "%.sum$", "%.min%.", "%.snap$", "%.svg$", "%.map$", "%.lcov$", "CHEATSHEET%.md$" }

---@param path string
---@return boolean
local function noisy(path)
  for _, p in ipairs(NOISE) do
    if path:find(p) then
      return true
    end
  end
  return false
end

--- Does this path add nothing worth reading in a diff (lockfiles, maps, snapshots)?
---@param path string
---@return boolean
function M.is_noise(path)
  return noisy(path)
end

---@param root string
---@return string stat  one line per file: `path +adds -dels`
function M.staged_numstat(root)
  local lines = {}
  for rec in (M.run({ "diff", "--cached", "--numstat", "--no-renames", "-z" }, root)):gmatch "[^%z]+" do
    local adds, dels, path = rec:match "^(%S+)\t(%S+)\t(.+)$"
    if path then
      lines[#lines + 1] = adds == "-" and (path .. " (binary)") or ("%s +%s -%s"):format(path, adds, dels)
    end
  end
  return table.concat(lines, "\n")
end

--- COMPACT staged diff for the model: no git headers (`diff --git`, `index`, `---`/`+++`), one `## path`
--- per file, little context (-U1), no noise (lockfiles, maps, snapshots) and with the cap split among
--- the files (one huge file does not leave the others without a diff).
---@param root string
---@param max integer character cap
---@return string diff, integer total_chars, boolean truncated  total = what it would take without trimming
function M.diff_for_ai(root, max)
  local raw = M.run({ "diff", "--cached", "-U1", "--no-color", "--no-ext-diff", "--no-renames" }, root)
  local files = {}
  for _, line in ipairs(vim.split(raw, "\n", { plain = true })) do
    local path = line:match "^diff %-%-git a/.- b/(.+)$"
    if path then
      files[#files + 1] = { path = path, tag = "", body = {} }
    elseif #files > 0 then
      local f = files[#files]
      if line:match "^new file mode" then
        f.tag = " (new)"
      elseif line:match "^deleted file mode" then
        f.tag = " (deleted)"
      elseif line:match "^Binary files" then
        f.tag = " (binary)"
      elseif
        not (
          line:match "^index "
          or line:match "^%-%-%- "
          or line:match "^%+%+%+ "
          or line:match "^old mode"
          or line:match "^new mode"
        )
      then
        f.body[#f.body + 1] = line
      end
    end
  end

  local total, sized = 0, {}
  for _, f in ipairs(files) do
    f.text = noisy(f.path) and "" or table.concat(f.body, "\n")
    f.noise = noisy(f.path)
    f.size = #f.text
    total = total + f.size
    sized[#sized + 1] = f
  end
  -- split: small ones fit whole and what is left over goes to the big ones
  table.sort(sized, function(a, b)
    return a.size < b.size
  end)
  local left, truncated = max, false
  for i, f in ipairs(sized) do
    local share = math.max(300, math.floor(left / (#sized - i + 1)))
    if f.size > share then
      f.text = f.text:sub(1, share) .. "\n[… cut]"
      truncated = true
    end
    left = left - math.min(f.size, share)
  end

  local parts = {}
  for _, f in ipairs(files) do
    local head = "## " .. f.path .. f.tag .. (f.noise and " (generated, diff omitted)" or "")
    parts[#parts + 1] = f.text ~= "" and (head .. "\n" .. f.text) or head
  end
  return table.concat(parts, "\n"), total, truncated
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

--- Is HEAD already on some remote? (rewriting it would break others' history)
---@param root string
---@return boolean
function M.head_on_remote(root)
  return out({ "branch", "-r", "--contains", "HEAD" }, root) ~= ""
end

--- Commits what is staged. `cb(ok, hash_or_error)`
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
