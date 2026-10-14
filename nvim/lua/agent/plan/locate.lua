-- ── Where a change reaches ───────────────────────────────────────────────────
-- From the symbol you are on, the places in the project that mention it, collapsed to the DECLARATION each one lives in
-- (the function or type, with its first line as the signature): that list is all a plan needs to see, a few dozen lines
-- instead of the files. Hits come from the language server (references) or, without one, from `git grep`.
-- `collapse` and `rank` are pure: the declarations lookup is passed in.
local M = {}

---@class AgentPlanSite
---@field path string       relative to the project root
---@field abs string
---@field name string
---@field kind "function"|"class"
---@field first integer
---@field last integer
---@field signature string  the declaration's first line
---@field hits integer      how many mentions fall inside it
---@field test boolean
---@field seed boolean?     the declaration the plan started from

---@param path string
---@return boolean
function M.is_test(path)
  return path:find "_test%." ~= nil
    or path:find "%.test%." ~= nil
    or path:find "%.spec%." ~= nil
    or path:find "/tests?/" ~= nil
end

--- Mentions → the declarations that hold them
---@param hits { abs: string, lnum: integer }[]
---@param decls_of fun(abs: string): { name: string, kind: string, first: integer, last: integer, signature: string }[]
---@param root string
---@return AgentPlanSite[]
function M.collapse(hits, decls_of, root)
  local by_key, order = {}, {}
  for _, hit in ipairs(hits) do
    local best
    for _, d in ipairs(decls_of(hit.abs)) do
      if d.first <= hit.lnum and hit.lnum <= d.last and (not best or (d.last - d.first) < (best.last - best.first)) then
        best = d
      end
    end
    if best then
      local key = hit.abs .. ":" .. best.first
      if not by_key[key] then
        local rel = hit.abs:sub(1, #root + 1) == root .. "/" and hit.abs:sub(#root + 2) or hit.abs
        by_key[key] = {
          path = rel,
          abs = hit.abs,
          name = best.name,
          kind = best.kind,
          first = best.first,
          last = best.last,
          signature = best.signature,
          hits = 0,
          test = M.is_test(rel),
        }
        order[#order + 1] = key
      end
      by_key[key].hits = by_key[key].hits + 1
    end
  end
  return vim.tbl_map(function(k)
    return by_key[k]
  end, order)
end

--- The sites the plan prompt shows: the seed's file first, then the files with most mentions, tests last; within a file in
--- order of appearance; capped by files and by sites
---@param sites AgentPlanSite[]
---@param limits { max_files: integer, max_sites: integer }
---@param seed_abs string?
---@return AgentPlanSite[]
function M.rank(sites, limits, seed_abs)
  local files, by_file = {}, {}
  for _, s in ipairs(sites) do
    if not by_file[s.abs] then
      by_file[s.abs] = { abs = s.abs, hits = 0, test = s.test, sites = {} }
      files[#files + 1] = by_file[s.abs]
    end
    local f = by_file[s.abs]
    f.hits = f.hits + s.hits
    table.insert(f.sites, s)
  end
  table.sort(files, function(a, b)
    local a_seed, b_seed = a.abs == seed_abs, b.abs == seed_abs
    if a_seed ~= b_seed then
      return a_seed
    end
    if a.test ~= b.test then
      return not a.test
    end
    if a.hits ~= b.hits then
      return a.hits > b.hits
    end
    return a.abs < b.abs
  end)
  local out = {}
  for i, f in ipairs(files) do
    if i > limits.max_files then
      break
    end
    table.sort(f.sites, function(a, b)
      return a.first < b.first
    end)
    for _, s in ipairs(f.sites) do
      if #out >= limits.max_sites then
        return out
      end
      out[#out + 1] = s
    end
  end
  return out
end

--- The declarations (functions and types) of a file, with their first line, from treesitter
---@param abs string
---@return table[]
function M.declarations(abs)
  local buf = vim.fn.bufadd(abs)
  vim.fn.bufload(buf)
  if vim.bo[buf].filetype == "" then
    local ft = vim.filetype.match { buf = buf, filename = abs }
    if ft then
      vim.bo[buf].filetype = ft
    end
  end
  local scopes = require "agent.context.scopes"
  local out = {}
  local function sig(first)
    return vim.trim(vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or ""):sub(1, 120)
  end
  for _, f in ipairs(scopes.functions(buf)) do
    if f.name then
      out[#out + 1] = { name = f.name, kind = "function", first = f.first, last = f.last, signature = sig(f.first) }
    end
  end
  for _, t in ipairs(scopes.type_declarations(buf)) do
    if t.name then
      out[#out + 1] = { name = t.name, kind = "class", first = t.first, last = t.last, signature = sig(t.first) }
    end
  end
  return out
end

--- Mentions of `name` through the language server (references), or nil when none can answer
---@param seed AgentTarget
---@param cb fun(hits: { abs: string, lnum: integer }[]?)
function M.references(seed, cb)
  local clients = vim.lsp.get_clients { bufnr = seed.buf, method = "textDocument/references" }
  local row, col = require("agent.context.target").name_position(seed)
  if #clients == 0 or not row then
    return cb(nil)
  end
  local line = vim.api.nvim_buf_get_lines(seed.buf, row, row + 1, false)[1] or ""
  local ok, character = pcall(vim.str_utfindex, line, clients[1].offset_encoding or "utf-16", col)
  local done = false
  local function finish(hits)
    if not done then
      done = true
      cb(hits)
    end
  end
  vim.defer_fn(function()
    finish(nil)
  end, 3000)
  vim.lsp.buf_request(seed.buf, "textDocument/references", {
    textDocument = vim.lsp.util.make_text_document_params(seed.buf),
    position = { line = row, character = ok and character or col },
    context = { includeDeclaration = true },
  }, function(_, result)
    local hits = {}
    for _, loc in ipairs(result or {}) do
      local uri = loc.uri or loc.targetUri
      local range = loc.range or loc.targetSelectionRange
      if uri and range then
        hits[#hits + 1] = { abs = vim.uri_to_fname(uri), lnum = range.start.line + 1 }
      end
    end
    finish(#hits > 0 and hits or nil)
  end)
end

--- Mentions of `name` found by text (`git grep`, then `rg`): the fallback without a language server
---@param name string
---@param root string
---@return { abs: string, lnum: integer }[]
function M.grep(name, root)
  local res = vim
    .system({ "git", "grep", "-n", "-w", "-I", "-F", "--no-color", "--", name }, { cwd = root, text = true })
    :wait(4000)
  if res.code ~= 0 then
    res = vim
      .system(
        { "rg", "--line-number", "--word-regexp", "--fixed-strings", "--no-heading", "--color=never", name },
        { cwd = root, text = true }
      )
      :wait(4000)
  end
  local hits = {}
  for line in (res.stdout or ""):gmatch "[^\r\n]+" do
    local path, lnum = line:match "^(.-):(%d+):"
    if path then
      hits[#hits + 1] = { abs = root .. "/" .. path, lnum = tonumber(lnum) }
    end
  end
  return hits
end

--- The sites for a seed: references if there is an LSP, text otherwise
---@param seed AgentTarget
---@param root string
---@param limits { max_files: integer, max_sites: integer }
---@param cb fun(sites: AgentPlanSite[], how: "lsp"|"grep")
function M.sites(seed, root, limits, cb)
  local seed_abs = vim.api.nvim_buf_get_name(seed.buf)
  local function done(hits, how)
    local sites = M.collapse(hits, M.declarations, root)
    for _, s in ipairs(sites) do
      s.seed = s.abs == seed_abs and s.first <= seed.first and seed.first <= s.last
    end
    cb(M.rank(sites, limits, seed_abs), how)
  end
  M.references(seed, function(hits)
    if hits then
      -- a language server that never leaves the seed's own file (it did not resolve the project, or the symbol is local)
      -- tells nothing about where the change reaches: the text search completes it
      local outside = false
      for _, h in ipairs(hits) do
        outside = outside or h.abs ~= seed_abs
      end
      if outside then
        return done(hits, "lsp")
      end
      return done(vim.list_extend(hits, M.grep(seed.name, root)), "lsp+grep")
    end
    done(M.grep(seed.name, root), "grep")
  end)
end

return M
