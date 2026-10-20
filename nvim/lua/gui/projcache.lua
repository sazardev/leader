-- ── Desktop app: what the project picker already knows ──────────────────────
-- One JSON file in the state folder (stdpath("state")/leader-projects-cache.json): the
-- git projects the last search found (and when), and the facts shown for each
-- one (branch, changes, last commit, stack, README) with the stamp they were
-- read at. A stamp is three stats (the folder, .git/HEAD, .git/index): while it
-- holds, nothing is read again, so moving over the list never touches git and
-- the home folder is searched again only every `settings.gui.projects.rescan`.
-- Read once per session, written when the picker closes or a search ends.
local M = {}

M.FILE = vim.fn.stdpath "state" .. "/leader-projects-cache.json"
M.KEEP = 400 -- facts kept for at most this many folders (the ones seen last stay)

local data

---@return { found: string[], found_at: integer, info: table<string, table> }
function M.get()
  if data then
    return data
  end
  data = {}
  local f = io.open(M.FILE)
  if f then
    local ok, decoded = pcall(vim.json.decode, f:read "*a")
    f:close()
    data = ok and type(decoded) == "table" and decoded or {}
  end
  data.found = type(data.found) == "table" and data.found or {}
  data.found_at = tonumber(data.found_at) or 0
  data.info = type(data.info) == "table" and data.info or {}
  return data
end

--- Writes the cache when something changed since the last write.
function M.save()
  if not (data and data.dirty) then
    return
  end
  data.dirty = nil
  -- only the folders seen last keep their facts
  local dirs = vim.tbl_keys(data.info)
  if #dirs > M.KEEP then
    table.sort(dirs, function(a, b)
      return (data.info[a].seen or 0) > (data.info[b].seen or 0)
    end)
    for i = M.KEEP + 1, #dirs do
      data.info[dirs[i]] = nil
    end
  end
  vim.fn.mkdir(vim.fs.dirname(M.FILE), "p")
  local f = io.open(M.FILE, "w")
  if f then
    f:write(vim.json.encode { found = data.found, found_at = data.found_at, info = data.info })
    f:close()
  end
end

--- Forgets what was read in this session (tests, or a file written by someone else).
function M.reset()
  data = nil
end

--- What changes when a project does: a new file at the top (README, go.mod), a commit or a checkout, a `git add`.
---@param dir string
---@return string
function M.stamp(dir)
  local parts = {}
  for _, p in ipairs { dir, dir .. "/.git/HEAD", dir .. "/.git/index" } do
    local st = vim.uv.fs_stat(p)
    parts[#parts + 1] = st and (st.mtime.sec .. "." .. st.mtime.nsec) or "-"
  end
  return table.concat(parts, "|")
end

--- The facts saved for `dir` while its stamp still holds.
---@param dir string
---@param stamp string
---@return table?
function M.info(dir, stamp)
  local info = M.get().info[dir]
  if info and info.stamp == stamp then
    info.seen = os.time()
    return info
  end
end

---@param dir string
---@param info table
function M.put(dir, info)
  local d = M.get()
  info.seen = os.time()
  d.info[dir] = info
  d.dirty = true
end

--- The folders the last search found and how old that search is (seconds).
---@return string[] dirs, integer age
function M.found()
  local d = M.get()
  return d.found, os.time() - d.found_at
end

---@param dirs string[]
function M.set_found(dirs)
  local d = M.get()
  d.found, d.found_at, d.dirty = dirs, os.time(), true
end

return M
