-- WHO CALLS the target, requested from the LSP (references): what refactoring needs and fixing never does. Each caller is one
-- short line (`path:line  code`), at most `settings.agent.context.callers` of them and at most two per file, so a refactor
-- sees how the function is really used before it changes a signature. Asynchronous with a wait cap, like `callees`:
-- whatever the LSP does not answer in time is omitted. Opt-in per action (refactor, the api lens): ~60 tokens per caller.
local settings = require("core.settings").agent.context

local PER_FILE = 2
local LINE_MAX = 140

---@param path string
---@param cache table<string, string[]>
---@return string[]
local function lines_of(path, cache)
  if not cache[path] then
    local buf = vim.fn.bufnr(path)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      cache[path] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    else
      local ok, lines = pcall(vim.fn.readfile, path)
      cache[path] = ok and lines or {}
    end
  end
  return cache[path]
end

--- The lines for a list of LSP locations: same file as the target first, then the others, a couple per file
---@param locations table[] LSP Location[]
---@param target AgentTarget
---@param limit integer
---@return string[]
local function format(locations, target, limit)
  local here = vim.api.nvim_buf_get_name(target.buf)
  local items = {}
  for _, loc in ipairs(locations) do
    local uri = loc.uri or loc.targetUri
    local range = loc.range or loc.targetSelectionRange
    if uri and range then
      local path = vim.uri_to_fname(uri)
      local lnum = range.start.line + 1
      -- a call from inside the target itself (recursion) says nothing new
      if not (path == here and lnum >= target.first and lnum <= target.last) then
        items[#items + 1] = { path = path, lnum = lnum }
      end
    end
  end
  table.sort(items, function(a, b)
    local a_here, b_here = a.path == here, b.path == here
    if a_here ~= b_here then
      return a_here
    end
    if a.path ~= b.path then
      return a.path < b.path
    end
    return a.lnum < b.lnum
  end)
  local out, per_file, cache = {}, {}, {}
  for _, item in ipairs(items) do
    per_file[item.path] = (per_file[item.path] or 0) + 1
    if per_file[item.path] <= PER_FILE then
      local code = vim.trim(lines_of(item.path, cache)[item.lnum] or "")
      local rel = vim.fn.fnamemodify(item.path, ":.")
      out[#out + 1] = ("%s:%d  %s%s"):format(
        rel,
        item.lnum,
        code:sub(1, LINE_MAX),
        rel:find("test", 1, true) and "  (test)" or ""
      )
      if #out >= limit then
        break
      end
    end
  end
  return out
end

return {
  cap = 1800,
  format = format,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local clients = vim.lsp.get_clients { bufnr = target.buf, method = "textDocument/references" }
    local row, col = require("agent.context.target").name_position(target)
    if #clients == 0 or not row then
      return done(nil)
    end
    local line = vim.api.nvim_buf_get_lines(target.buf, row, row + 1, false)[1] or ""
    local ok, character = pcall(vim.str_utfindex, line, clients[1].offset_encoding or "utf-16", col)
    local finished = false
    local function finish(text)
      if not finished then
        finished = true
        done(text)
      end
    end
    vim.defer_fn(function()
      finish(nil)
    end, settings.hover_timeout_ms * 2)
    vim.lsp.buf_request(target.buf, "textDocument/references", {
      textDocument = vim.lsp.util.make_text_document_params(target.buf),
      position = { line = row, character = ok and character or col },
      context = { includeDeclaration = false },
    }, function(_, result)
      local lines = format(result or {}, target, settings.callers)
      finish(#lines > 0 and ("Where %s is called from:\n%s"):format(target.name, table.concat(lines, "\n")) or nil)
    end)
  end,
}
