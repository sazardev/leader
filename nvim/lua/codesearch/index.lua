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
---@param cb fun(files: string[]) files relative to the root; rg runs apart from the UI, 30k files are not instant
local function list_files(root, cb)
  local cmd = { "rg", "--files", "--max-filesize", tostring(settings.max_bytes) }
  for _, dir in ipairs(settings.exclude) do
    vim.list_extend(cmd, { "--glob", "!" .. dir })
  end
  vim.list_extend(cmd, require("utils.generated").rg_excludes()) -- x.g.dart, x.freezed.dart, x.pb.go: the source has the names
  vim.system(cmd, { cwd = root, text = true }, function(out)
    vim.schedule(function()
      local files = {}
      for line in (out.stdout or ""):gmatch "[^\r\n]+" do
        files[#files + 1] = line
      end
      table.sort(files)
      cb(files)
    end)
  end)
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

--- Reads `todo` in this process, in slices of ~12 ms: the UI keeps breathing between them
---@param root string
---@param todo { rel: string, lang: string, stamp: string }[]
---@param proj table
---@param done fun()
local function read_here(root, todo, proj, done)
  local i = 0
  local function slice()
    local t0 = vim.uv.hrtime()
    while i < #todo and (vim.uv.hrtime() - t0) < 12e6 do
      i = i + 1
      local item = todo[i]
      local f = io.open(root .. "/" .. item.rel, "rb")
      local text = f and f:read "*a"
      if f then
        f:close()
      end
      proj.files[item.rel] = { stamp = item.stamp, symbols = text and M.read(item.rel, text, item.lang) or {} }
    end
    if i < #todo then
      return vim.defer_fn(slice, 1)
    end
    done()
  end
  slice()
end

--- Reads `todo` in headless Neovims running side by side (codesearch/worker.lua): nothing is parsed in the editor, and
--- N workers take about 1/N of the time. A worker that fails leaves its files to `read_here`.
---@param root string
---@param todo { rel: string, lang: string, stamp: string }[]
---@param proj table
---@param done fun()
local function read_apart(root, todo, proj, done)
  scopes.ensure_plugin() -- the workers take our runtimepath: the queries' plugin must be on it by now
  local n = math.min(settings.workers, math.ceil(#todo / settings.workers_min))
  local parts = {}
  for k = 1, n do
    parts[k] = {}
  end
  for i, item in ipairs(todo) do
    table.insert(parts[(i - 1) % n + 1], item) -- interleaved: big files are spread out
  end
  local pending, failed = n, {}
  local function settle()
    pending = pending - 1
    if pending > 0 then
      return
    end
    if #failed > 0 then
      return read_here(root, failed, proj, done)
    end
    done()
  end
  for _, items in ipairs(parts) do
    local job, out = vim.fn.tempname(), vim.fn.tempname()
    vim.fn.writefile({ vim.json.encode { root = root, out = out, items = items } }, job)
    local ok = pcall(vim.system, {
      vim.v.progpath,
      "--headless",
      "-n",
      "-u",
      "NONE", -- no config and no plugins to load: it takes this editor's runtimepath, so same parsers and queries
      "-c",
      "lua vim.o.runtimepath = vim.env.CODESEARCH_RTP; require('codesearch.worker').run()",
    }, { env = { CODESEARCH_JOB = job, CODESEARCH_RTP = vim.o.runtimepath }, text = true }, function(res)
      vim.schedule(function()
        local f = res.code == 0 and io.open(out, "rb")
        local text = f and f:read "*a"
        if f then
          f:close()
        end
        local decoded, data = pcall(vim.json.decode, text or "")
        if decoded and type(data) == "table" then
          for rel, entry in pairs(data) do
            proj.files[rel] = entry
          end
        else
          vim.list_extend(failed, items)
        end
        os.remove(job)
        os.remove(out)
        settle()
      end)
    end)
    if not ok then
      vim.list_extend(failed, items)
      os.remove(job)
      settle()
    end
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
  list_files(root, function(files)
    local capped = math.min(#files, settings.max_files)
    local stats = { files = capped, read = 0, skipped = #files - capped }
    local live, todo, i = {}, {}, 0
    local removed = 0

    local function finish()
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
      stats.read = #todo
      cb(list, stats)
      -- after the picker is up: encoding the index is a few ms the user should not wait for
      if stats.read > 0 or removed > 0 then
        vim.defer_fn(function()
          store.save(root, proj.files)
        end, 50)
      end
    end

    -- first pass: which files changed since the stored index (a stat each, in slices)
    local function scan()
      local t0 = vim.uv.hrtime()
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
            todo[#todo + 1] = { rel = rel, lang = lang, stamp = stamp }
          end
        end
      end
      if progress then
        progress(i, capped)
      end
      if i < capped then
        return vim.defer_fn(scan, 1)
      end
      if settings.workers > 0 and #todo >= settings.workers_min then
        read_apart(root, todo, proj, finish)
      else
        read_here(root, todo, proj, finish)
      end
    end
    scan()
  end)
end

return M
