-- ── What git knows about a conflict ──────────────────────────────────────────
-- The files in conflict, and the story of a merge in a few lines the model can use: which two lines of work meet, what
-- each one did (commit subjects) and what each changed against the common ancestor (stages 1, 2 and 3 of the index).
-- Read-only git, asynchronous, nothing is ever staged or changed here (`stage` is the one exception and is asked first).
local settings = require("core.settings").agent.conflict

local M = {}

--- Runs git; `cb(stdout or nil)` (nil on failure)
---@param root string
---@param args string[]
---@param cb fun(out: string?)
function M.run(root, args, cb)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  local ok = pcall(vim.system, cmd, { text = true, timeout = 10000 }, function(res)
    vim.schedule(function()
      cb(res.code == 0 and res.stdout or nil)
    end)
  end)
  if not ok then
    cb(nil)
  end
end

--- Runs several git commands at once; `cb(outs)` when all are back (outs[i] = stdout or nil)
---@param root string
---@param list string[][]
---@param cb fun(outs: (string?)[])
local function all(root, list, cb)
  local outs, left = {}, #list
  if left == 0 then
    return cb(outs)
  end
  for i, args in ipairs(list) do
    M.run(root, args, function(out)
      outs[i] = out
      left = left - 1
      if left == 0 then
        cb(outs)
      end
    end)
  end
end

--- The other side of the operation in progress: the ref its HEAD file names, and what the operation is
---@param root string
---@return string? ref, string? kind
function M.theirs(root)
  local res = vim.system({ "git", "-C", root, "rev-parse", "--git-dir" }, { text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  local dir = vim.trim(res.stdout)
  if not dir:match "^/" then
    dir = root .. "/" .. dir
  end
  for _, c in ipairs {
    { "MERGE_HEAD", "merge" },
    { "REBASE_HEAD", "rebase" },
    { "CHERRY_PICK_HEAD", "cherry-pick" },
    { "REVERT_HEAD", "revert" },
  } do
    if vim.uv.fs_stat(dir .. "/" .. c[1]) then
      return c[1], c[2]
    end
  end
  return nil
end

--- The files git lists as unmerged (relative to the repository), with their absolute path
---@param root string
---@param cb fun(files: { path: string, abs: string }[])
function M.files(root, cb)
  M.run(root, { "diff", "--name-only", "--diff-filter=U" }, function(out)
    local files = {}
    for line in (out or ""):gmatch "[^\n]+" do
      files[#files + 1] = { path = line, abs = root .. "/" .. line }
    end
    cb(files)
  end)
end

---@param text string?
---@param max integer
---@return string
local function clip(text, max)
  text = text or ""
  if #text <= max then
    return text
  end
  return text:sub(1, max) .. "\n… (cut)"
end

---@param out string?
---@return string[]
local function subjects(out)
  local list = {}
  for line in (out or ""):gmatch "[^\n]+" do
    list[#list + 1] = "- " .. line
  end
  return list
end

--- The story of the conflicts of one file, as the text of the `merge` section sent with every conflict
---@param root string
---@param path string relative to the repository
---@param cb fun(text: string)
function M.context(root, path, cb)
  local theirs, kind = M.theirs(root)
  local n = tostring(settings.log)
  local list = {
    { "branch", "--show-current" },
    { "diff", "-U2", ":1:" .. path, ":2:" .. path },
    { "diff", "-U2", ":1:" .. path, ":3:" .. path },
  }
  if theirs then
    vim.list_extend(list, {
      { "log", "--no-merges", "-n", n, "--format=%h %s", "HEAD", "^" .. theirs, "--", path },
      { "log", "--no-merges", "-n", n, "--format=%h %s", theirs, "^HEAD", "--", path },
      { "name-rev", "--name-only", "--exclude=refs/tags/*", theirs },
    })
  end
  all(root, list, function(outs)
    local branch = vim.trim(outs[1] or "")
    local lines = {}
    lines[#lines + 1] = kind and ("A %s is in progress%s."):format(kind, branch ~= "" and (" on " .. branch) or "")
      or "No merge is in progress (the markers are in the file only)."
    if kind == "rebase" then
      lines[#lines + 1] = "In a rebase, ours = the branch being rebased onto, theirs = the commit being replayed."
    end
    if theirs then
      local ours_log, theirs_log = subjects(outs[4]), subjects(outs[5])
      local other = vim.trim(outs[6] or "")
      if #ours_log > 0 then
        lines[#lines + 1] = ("Ours (%s) did, newest first:"):format(branch ~= "" and branch or "HEAD")
        vim.list_extend(lines, ours_log)
      end
      if #theirs_log > 0 then
        lines[#lines + 1] = ("Theirs (%s) did, newest first:"):format(other ~= "" and other or theirs)
        vim.list_extend(lines, theirs_log)
      end
    end
    for i, who in ipairs { "ours", "theirs" } do
      local diff = vim.trim(outs[i + 1] or "")
      if diff ~= "" then
        lines[#lines + 1] = ("What %s changed in this file against the common ancestor:"):format(who)
        lines[#lines + 1] = clip(diff, settings.diff_chars)
      end
    end
    cb(table.concat(lines, "\n"))
  end)
end

--- `git add` of a file (the way a resolved file is told to git)
---@param root string
---@param path string
---@param cb fun(ok: boolean)
function M.stage(root, path, cb)
  M.run(root, { "add", "--", path }, function(out)
    cb(out ~= nil)
  end)
end

return M
