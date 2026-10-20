-- ── Code search: the symbol index ────────────────────────────────────────────
-- Every named function and type of the project, read with treesitter (the same `textobjects` queries the agent uses, so
-- every language with a parser works with no per-language code). Built in slices so the editor never freezes, kept in
-- memory per project (and on disk, codesearch/store.lua) and refreshed per file by mtime+size: asking again, in this
-- session or the next, only re-reads what changed.
local rank = require "codesearch.rank"
local store = require "codesearch.store"
local scopes = require "agent.context.scopes"
local settings = require("core.settings").search

local M = {}

---@type table<string, { files: table<string, { stamp: string, symbols: CodeSymbol[] }>, list: CodeSymbol[]? }>
local projects = {}

local COMMENT = { "^%s*//", "^%s*#", "^%s*%-%-", "^%s*%*", "^%s*/%*", '^%s*"""', "^%s*;;" }

---@param line string
---@return boolean
local function comment_line(line)
  for _, p in ipairs(COMMENT) do
    if line:find(p) then
      return true
    end
  end
  return false
end

--- The comment block right above a line (doc comments say what it is FOR: the best words for a question)
---@param lines string[]
---@param first integer 1-based
---@return string?
local function doc_above(lines, first)
  local parts, row = {}, first - 1
  while row >= 1 and #parts < 4 and comment_line(lines[row]) do
    table.insert(parts, 1, (lines[row]:gsub('^%s*[/#*%-;"]+%s*', "")))
    row = row - 1
  end
  return #parts > 0 and table.concat(parts, " ") or nil
end

--- Symbols of one file's text
---@param rel string path relative to the project
---@param text string
---@param lang string
---@return CodeSymbol[]
function M.read(rel, text, lang)
  local lines = vim.split(text, "\n", { plain = true })
  local out = {}
  for _, s in ipairs(scopes.symbols(text, lang)) do
    out[#out + 1] = {
      name = s.name,
      kind = s.kind,
      path = rel,
      line = s.first,
      sig = vim.trim(lines[s.first] or ""):sub(1, 140),
      doc = doc_above(lines, s.first),
    }
  end
  return out
end

---@param root string
---@return string[] files relative to the root
local function list_files(root)
  local cmd = { "rg", "--files", "--max-filesize", tostring(settings.max_bytes) }
  for _, dir in ipairs(settings.exclude) do
    vim.list_extend(cmd, { "--glob", "!" .. dir })
  end
  vim.list_extend(cmd, require("utils.generated").rg_excludes()) -- x.g.dart, x.freezed.dart, x.pb.go: the source has the names
  local out = vim.system(cmd, { cwd = root, text = true }):wait()
  local files = {}
  for line in (out.stdout or ""):gmatch "[^\r\n]+" do
    files[#files + 1] = line
  end
  table.sort(files)
  return files
end

---@param rel string
---@return string?
local function lang_of(rel)
  local ft = vim.filetype.match { filename = rel }
  return ft and vim.treesitter.language.get_lang(ft) or nil
end

---@param root string
---@return table
local function project(root)
  projects[root] = projects[root] or { files = store.load(root) or {} }
  return projects[root]
end

--- Forgets the index of a project (it is rebuilt on the next search)
---@param root string?
function M.drop(root)
  if root then
    projects[root] = nil
    store.delete(root)
  else
    for r in pairs(projects) do
      store.delete(r)
    end
    projects = {}
  end
end

--- Forgets what is in memory only, as a new session would (the copy on disk stays)
---@param root string?
function M.unload(root)
  if root then
    projects[root] = nil
  else
    projects = {}
  end
end

--- Builds or refreshes the index of `root`. `cb(list, stats)` when done; `progress(done, total)` between slices.
---@param root string
---@param cb fun(list: CodeSymbol[], stats: { files: integer, read: integer, skipped: integer })
---@param progress fun(done: integer, total: integer)?
function M.build(root, cb, progress)
  if vim.fn.executable "rg" ~= 1 then
    return cb({}, { files = 0, read = 0, skipped = 0 })
  end
  local proj = project(root)
  local files = list_files(root)
  local capped = math.min(#files, settings.max_files)
  local stats = { files = capped, read = 0, skipped = #files - capped }
  local live, i = {}, 0
  local removed = 0

  local function slice()
    local t0 = vim.uv.hrtime()
    -- slices of ~12 ms: the UI keeps breathing between them
    while i < capped and (vim.uv.hrtime() - t0) < 12e6 do
      i = i + 1
      local rel = files[i]
      live[rel] = true
      local lang = lang_of(rel)
      local stat = lang and vim.uv.fs_stat(root .. "/" .. rel)
      if stat then
        local stamp = ("%d:%d"):format(stat.mtime.sec, stat.size)
        local cached = proj.files[rel]
        if not (cached and cached.stamp == stamp) then
          local f = io.open(root .. "/" .. rel, "rb")
          local text = f and f:read "*a"
          if f then
            f:close()
          end
          proj.files[rel] = { stamp = stamp, symbols = text and M.read(rel, text, lang) or {} }
          stats.read = stats.read + 1
        end
      end
    end
    if progress then
      progress(i, capped)
    end
    if i < capped then
      return vim.defer_fn(slice, 1)
    end
    local list = {}
    for rel, entry in pairs(proj.files) do
      if live[rel] then
        vim.list_extend(list, entry.symbols)
      else
        proj.files[rel] = nil -- deleted or moved since the last time
        removed = removed + 1
      end
    end
    table.sort(list, function(a, b)
      if a.path ~= b.path then
        return a.path < b.path
      end
      return a.line < b.line
    end)
    proj.list = list
    cb(list, stats)
    -- after the picker is up: encoding the index is a few ms the user should not wait for
    if stats.read > 0 or removed > 0 then
      vim.defer_fn(function()
        store.save(root, proj.files)
      end, 50)
    end
  end
  slice()
end

return M
