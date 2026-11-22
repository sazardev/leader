-- ── Python attribute completion (blink source, 0 tokens) ──────────────────────
-- basedpyright takes ~1 s to answer `pd.` at a NEW position (it caches completions per position, and every keystroke
-- invalidates the old one). This source reads the names a module actually exports from its installed stubs/source,
-- caches them by mtime+size, and offers them immediately. The LSP source still supplies the typed, documented items;
-- these only stop the menu from appearing empty while it works. Nothing is executed and no process is started.
local imports = require "utils.pyimports"
local pyproject = require "utils.python"

local M = {}
local KIND = vim.lsp.protocol.CompletionItemKind
local Source = {}
Source.__index = Source

local MAX_NAMES = 400
local MAX_CACHE = 24
local cache, alias_cache = {}, {}

local function settings()
  return require("core.settings").python or {}
end

--- Top-level names a `.py`/`.pyi` module exports: `from x import y`, `def y`, `class y`, `import y`.
--- Pure; private names (leading `_`) are left out. Multiline `import (...)` blocks are supported.
---@param text string
---@return string[]
function M.parse(text)
  local out, seen = {}, {}
  local function add(name)
    if name and name ~= "_" and not name:match "^_" and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  local in_block = false
  for line in text:gmatch "[^\r\n]+" do
    if in_block then
      add(line:match "^%s*([%w_]+)")
      if line:find(")", 1, true) then
        in_block = false
      end
    elseif line:match "^%s*from%s+[%w_.]+%s+import%s+%(%s*$" then
      in_block = true
    else
      add(line:match "^%s*from%s+[%w_.]+%s+import%s+([%w_]+)")
      local module = line:match "^%s*import%s+([%w_.]+)"
      if module then
        add(module:match "^([%w_]+)")
      end
      add(line:match "^%s*def%s+([%w_]+)")
      add(line:match "^%s*async%s+def%s+([%w_]+)")
      add(line:match "^%s*class%s+([%w_]+)")
    end
  end
  return out
end

local function site_packages(root)
  local dirs = vim.fn.glob(root .. "/.venv/lib/python*/site-packages", true, true)
  if #dirs == 0 then
    dirs = vim.fn.glob(root .. "/venv/lib/python*/site-packages", true, true)
  end
  return dirs[1]
end

local function module_path(site, module)
  local rel = module:gsub("%.", "/")
  local stub = rel:gsub("^([^/]+)", "%1-stubs")
  for _, path in ipairs {
    site .. "/" .. stub .. ".pyi",
    site .. "/" .. stub .. "/__init__.pyi",
    site .. "/" .. rel .. ".pyi",
    site .. "/" .. rel .. "/__init__.pyi",
    site .. "/" .. rel .. ".py",
    site .. "/" .. rel .. "/__init__.py",
  } do
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

--- Methods declared inside a class in a stub/source file (pure). Only the class block is read; inherited members
--- come from the LSP later. Names are deduplicated (overloaded `def groupby` appears several times).
---@param text string
---@param class string
---@return string[]
function M.class_members(text, class)
  local out, seen, inside = {}, {}, false
  for line in text:gmatch "[^\r\n]+" do
    if not inside then
      if line:match("^%s*class%s+([%w_]+)") == class then
        inside = true
      end
    elseif line:match "^%S" then -- first column: the class block ended
      break
    else
      local name = line:match "^%s+def%s+([%w_]+)"
        or line:match "^%s+async%s+def%s+([%w_]+)"
      if name and name ~= "_" and not name:match "^_" and not seen[name] then
        seen[name] = true
        out[#out + 1] = name
      end
    end
  end
  return out
end

local PANDAS_CLASS_STUBS = {
  DataFrame = "pandas-stubs/core/frame.pyi",
  Series = "pandas-stubs/core/series.pyi",
}

--- Cached exported names of an installed module (empty when it is not installed or not readable).
---@param root string project root
---@param module string dotted module name
---@return string[]
function M.names(root, module)
  local site = site_packages(root)
  if not site then
    return {}
  end
  local parent, last = module:match "^(.*)%.([%w_]+)$"
  local class = parent == "pandas" and PANDAS_CLASS_STUBS[last] and last or nil
  local path = class and (site .. "/" .. PANDAS_CLASS_STUBS[class]) or module_path(site, module)
  if not path then
    return {}
  end
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return {}
  end
  local key = path .. ":" .. stat.mtime.sec .. ":" .. stat.size .. ":" .. (class or "")
  if cache[key] then
    return cache[key]
  end
  local file = io.open(path, "r")
  if not file then
    return {}
  end
  local text = file:read(262144) -- a header + what is declared; large generated modules are truncated
  file:close()
  local names = class and M.class_members(text or "", class) or M.parse(text or "")
  if #names > MAX_NAMES then
    names = vim.list_slice(names, 1, MAX_NAMES)
  end
  if #cache >= MAX_CACHE then
    cache = {}
  end
  cache[key] = names
  return names
end

function M.reset()
  cache, alias_cache = {}, {}
end

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "python"
end

local function empty()
  return { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
end

--- Variables assigned from a pandas reader/constructor: `df = pd.read_csv(…)` → `pandas.DataFrame`.
--- Pure; only the aliases of the buffer are trusted, so a local variable named `pd` is never mistaken for pandas.
---@param lines string[]
---@param alias_map table<string, string>
---@return table<string, string>
function M.variables(lines, alias_map)
  local classes = { read_csv = "DataFrame", read_sql = "DataFrame", read_json = "DataFrame", DataFrame = "DataFrame", Series = "Series" }
  local out = {}
  for _, line in ipairs(lines) do
    local var, alias, method = line:match "^%s*([%w_]+)%s*=%s*([%w_]+)%.([%w_]+)%s*%("
    local class = method and classes[method]
    if var and class and alias_map[alias] == "pandas" then
      out[var] = "pandas." .. class
    end
  end
  return out
end

local IMPORT_LINES = 300 -- imports and readers live at the top; never scan a whole 5k-line module on every keystroke

local function info(bufnr)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local key = bufnr .. ":" .. tick
  if not alias_cache[key] then
    if #alias_cache >= MAX_CACHE then
      alias_cache = {}
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, math.min(IMPORT_LINES, vim.api.nvim_buf_line_count(bufnr)), false)
    local found = imports.aliases(lines)
    alias_cache[key] = { aliases = found, variables = M.variables(lines, found) }
  end
  return alias_cache[key]
end

---@param ctx blink.cmp.Context
---@param callback fun(response: table)
function Source:get_completions(ctx, callback)
  local cfg = settings().attributes or {}
  if cfg.enabled == false then
    return callback(empty())
  end
  local before = ctx.line:sub(1, ctx.cursor[2])
  local word = before:match "[%w_]*$" or ""
  local alias = before:sub(1, #before - #word):match "([%w_]+)%.$"
  if not alias then
    return callback(empty())
  end
  local found = info(ctx.bufnr)
  local module = found.aliases[alias] or found.variables[alias]
  if not module then
    return callback(empty())
  end
  local root = pyproject.root(vim.fs.dirname(vim.api.nvim_buf_get_name(ctx.bufnr)))
  local line, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local range = {
    start = { line = line, character = math.max(col - #word, 0) },
    ["end"] = { line = line, character = col },
  }
  local items = {}
  for _, name in ipairs(M.names(root, module)) do
    items[#items + 1] = {
      label = name,
      kind = KIND.Variable,
      detail = module,
      textEdit = { range = range, newText = name },
    }
  end
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return M
