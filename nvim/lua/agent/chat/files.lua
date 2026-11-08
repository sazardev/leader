-- ── Project files for @mentions (listing, resolution, fuzzy filter) ──────────
-- One responsibility: know which files exist under the project root and turn a
-- path into its contents. `filter` is pure (tests); `list` caches for 30 s so
-- typing in the input never runs git on every key.
local M = {}

M.CACHE_MS = 30000

--- Root of the project the chat works on: the session's root when the chat is
--- loaded (the input buffer has no file of its own), else the git root above the
--- cursor, else the editor's cwd.
---@return string
function M.root()
  local w = package.loaded["agent.chat.window"]
  local session = w and w.session
  if session and session.root and session.root ~= "" then
    return session.root
  end
  return vim.fs.root(0, ".git") or (vim.uv.cwd() or "")
end

--- Tracked + untracked (not ignored) files, relative to the root, sorted.
---@param force boolean?
---@return string[]
function M.list(force)
  local root = M.root()
  local now = vim.uv.hrtime() / 1e6
  if not force and M._cache and M._cache.root == root and now - M._cache.at < M.CACHE_MS then
    return M._cache.list
  end
  local list = {}
  local out = vim.fn.systemlist { "git", "-C", root, "ls-files", "-co", "--exclude-standard" }
  if vim.v.shell_error == 0 then
    list = out
  else
    local ok, rg = pcall(vim.fn.systemlist, { "rg", "--files", "--hidden", "-g", "!.git" })
    if ok and vim.v.shell_error == 0 then
      list = rg
    end
  end
  list = vim.tbl_filter(function(p)
    return p ~= "" and not p:find "/%.git/" and not p:find "^%.git/"
  end, list)
  table.sort(list)
  M._cache = { root = root, list = list, at = now }
  return list
end

--- Forgets the cached listing (tests, or a file created outside).
function M.invalidate()
  M._cache = nil
end

--- Fuzzy-filter `files` for `query` (subsequence; prefix/substring win). Pure.
---@param files string[]
---@param query string
---@param limit integer?
---@return string[]
function M.filter(files, query, limit)
  limit = limit or 50
  query = (query or ""):lower()
  if query == "" then
    local out = {}
    for i = 1, math.min(limit, #files) do
      out[i] = files[i]
    end
    return out
  end
  local scored = {}
  for _, path in ipairs(files) do
    local lower = path:lower()
    local score
    local base = vim.fs.basename(lower)
    if lower:find(query, 1, true) == 1 then
      score = 100
    elseif base:find(query, 1, true) == 1 then
      score = 80
    elseif lower:find(query, 1, true) then
      score = 60
    else
      -- subsequence: "nch" → nvim/lua/agent/chat/...
      local from = 1
      local matched = true
      for i = 1, #query do
        local found = lower:find(query:sub(i, i), from, true)
        if not found then
          matched = false
          break
        end
        from = found + 1
      end
      if matched then
        score = 40
      end
    end
    if score then
      scored[#scored + 1] = { path = path, score = score - #path * 0.001 }
    end
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a.path < b.path
  end)
  local out = {}
  for i = 1, math.min(limit, #scored) do
    out[i] = scored[i].path
  end
  return out
end

--- Absolute path of `path`, relative to the project or the cwd. nil if absent.
---@param path string
---@return string?
function M.resolve(path)
  if path == "" then
    return nil
  end
  if vim.fn.filereadable(path) == 1 then
    return vim.fn.fnamemodify(path, ":p")
  end
  local root = M.root()
  local full = root .. "/" .. path
  if vim.fn.filereadable(full) == 1 then
    return full
  end
  for _, p in ipairs(M.list()) do
    if p == path or p:sub(-(#path + 1)) == "/" .. path then
      local candidate = root .. "/" .. p
      if vim.fn.filereadable(candidate) == 1 then
        return candidate
      end
    end
  end
  return nil
end

--- Content of a file: the unsaved buffer when it is open, the disk otherwise.
---@param path string
---@return string?
function M.read(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name == path or vim.fn.fnamemodify(name, ":p") == path then
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      end
    end
  end
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local body = f:read "*a"
  f:close()
  return body
end

return M
