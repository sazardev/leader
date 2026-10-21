-- ── What the last build wrote, so it can be taken back ───────────────────────
-- The build writes files straight to disk (no buffer, so no `u`). Every file it writes is journaled here: its path, a hash
-- of what was written, and, when it replaced a file, where that one went (files.ops.trash). `undo` puts it all back: replaced
-- files return from the trash, created files are deleted, empty folders the build made go too. Only the LAST build of a project
-- is kept, and a file you changed after the build is never touched: its hash no longer matches, so it is left and reported.
local ops = require "files.ops"

local M = {}

---@class BuildJournalEntry
---@field path string       relative to the project root
---@field hash string       sha256 of what the build wrote
---@field stored string?    where the replaced file waits in the trash (nil = the build created it)

---@class BuildJournal
---@field started integer   the run it belongs to (state.run.started)
---@field files BuildJournalEntry[]

---@param root string
---@return string
function M.path(root)
  return ("%s/agent-build-journal/%s.json"):format(vim.fn.stdpath "state", (root:gsub("[^%w%.%-]+", "_")))
end

---@param root string
---@return BuildJournal?
function M.load(root)
  local path = M.path(root)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and type(data) == "table" and data.files and data or nil
end

---@param root string
---@param journal BuildJournal?
local function save(root, journal)
  local path = M.path(root)
  if not journal then
    return vim.fn.delete(path)
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(vim.json.encode(journal), "\n", { plain = true }), path)
end

--- A file the build just wrote. `entry` is what files.ops.trash returned for the file it replaced, if there was one. A write
--- of a different run starts a new journal: only the last build is kept
---@param root string
---@param started integer
---@param path string
---@param content string
---@param entry { stored: string }?
function M.record(root, started, path, content, entry)
  local journal = M.load(root)
  if not journal or journal.started ~= started then
    journal = { started = started, files = {} }
  end
  -- a file written twice in a run (a fix round) keeps the FIRST replaced original, with the latest hash
  local first
  for i, e in ipairs(journal.files) do
    if e.path == path then
      first = table.remove(journal.files, i)
      break
    end
  end
  journal.files[#journal.files + 1] = {
    path = path,
    hash = vim.fn.sha256(content),
    stored = (first and first.stored) or (entry and entry.stored) or nil,
  }
  save(root, journal)
end

--- What `undo` would do: { files, created, replaced }, nil when there is no journal
---@param root string
---@return { files: integer, created: integer, replaced: integer }?
function M.last(root)
  local journal = M.load(root)
  if not journal or #journal.files == 0 then
    return nil
  end
  local replaced = 0
  for _, e in ipairs(journal.files) do
    replaced = replaced + (e.stored and 1 or 0)
  end
  return { files = #journal.files, created = #journal.files - replaced, replaced = replaced }
end

---@param path string
---@return string?
local function read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

--- Takes the last build back. Returns what happened per file
---@param root string
---@return { restored: integer, removed: integer, skipped: { path: string, why: string }[] }?
function M.undo(root)
  local journal = M.load(root)
  if not journal then
    return nil
  end
  local result = { restored = 0, removed = 0, skipped = {} }
  local dirs = {}
  for i = #journal.files, 1, -1 do
    local e = journal.files[i]
    local full = root .. "/" .. e.path
    local current = read(full)
    if not current then
      result.skipped[#result.skipped + 1] = { path = e.path, why = "gone" }
    elseif vim.fn.sha256(current) ~= e.hash then
      result.skipped[#result.skipped + 1] = { path = e.path, why = "edited since" }
    elseif e.stored then
      if ops.exists(e.stored) then
        vim.fn.delete(full)
        local ok = ops.rename(e.stored, full)
        if ok then
          result.restored = result.restored + 1
        else
          result.skipped[#result.skipped + 1] = { path = e.path, why = "could not restore the original" }
        end
      else
        result.skipped[#result.skipped + 1] = { path = e.path, why = "the original left the trash" }
      end
    else
      vim.fn.delete(full)
      result.removed = result.removed + 1
      local d = vim.fs.dirname(e.path)
      while d and d ~= "." and d ~= "" do
        dirs[d] = true
        d = vim.fs.dirname(d)
      end
    end
  end
  -- folders the build made: the deepest first, only the ones that are empty now
  local list = vim.tbl_keys(dirs)
  table.sort(list, function(a, b)
    return #a > #b
  end)
  for _, d in ipairs(list) do
    pcall(vim.uv.fs_rmdir, root .. "/" .. d)
  end
  -- what could not be undone stays in the journal (nothing else does)
  if #result.skipped == 0 then
    save(root, nil)
  else
    local left = {}
    for _, s in ipairs(result.skipped) do
      for _, e in ipairs(journal.files) do
        if e.path == s.path then
          left[#left + 1] = e
        end
      end
    end
    save(root, { started = journal.started, files = left })
  end
  return result
end

return M
