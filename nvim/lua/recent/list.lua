-- ── Recent files of a project: the pure part ─────────────────────────────────
-- What belongs in "recent files" for a project, from what is known (no I/O but `exists`, which is injected):
--   * `store`    the files you opened here, with when (recent/store.lua)
--   * `oldfiles` Neovim's own global list (newest first, no times): only what lies inside the project, after the
--                files the store knows, so a project you never opened with this feature still has a list
--   * `open`     the files open right now, they count as just used
-- A file belongs to the project when its path is inside the project's folder. Generated files, git's and plugin
-- files are never recent files.
local M = {}

M.SKIP = { "/%.git/", "/node_modules/", "/%.cache/", "COMMIT_EDITMSG$", "/lazy/", "/%.local/share/nvim/" }

---@param path string
---@param root string
---@return boolean
function M.inside(path, root)
  root = root:gsub("/+$", "")
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

---@param path string
---@return boolean
function M.recent_worthy(path)
  for _, pat in ipairs(M.SKIP) do
    if path:find(pat) then
      return false
    end
  end
  return true
end

---@class RecentEntry
---@field path string
---@field at integer? seconds; nil = from Neovim's oldfiles (known only to be older than the store's)

--- The list for `root` (or for every project when `root` is nil), newest first, without repeats.
---@param root string?
---@param src { store: RecentEntry[], oldfiles: string[], open: string[], exists: fun(p: string): boolean, now: integer, max: integer? }
---@return RecentEntry[]
function M.build(root, src)
  local seen, out = {}, {}
  local function add(path, at)
    if seen[path] or not M.recent_worthy(path) or (root and not M.inside(path, root)) or not src.exists(path) then
      return
    end
    seen[path] = true
    out[#out + 1] = { path = path, at = at }
  end
  for _, p in ipairs(src.open) do
    add(p, src.now)
  end
  local stored = vim.deepcopy(src.store)
  table.sort(stored, function(a, b)
    return (a.at or 0) > (b.at or 0)
  end)
  for _, e in ipairs(stored) do
    add(e.path, e.at)
  end
  for _, p in ipairs(src.oldfiles) do
    add(p, nil)
  end
  local max = src.max or 200
  while #out > max do
    table.remove(out)
  end
  return out
end

return M
