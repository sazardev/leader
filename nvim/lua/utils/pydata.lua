-- ── Python data files: path and column completion (blink source, `python`) ────
-- Inside a reader call (`pd.read_csv("data/…")`) it lists the project's real data files, filtered by reader. Once a
-- variable is assigned (`df = pd.read_csv(...)`), `df["…` and `df.…` complete the columns of THAT file. Text formats
-- are parsed in Lua from the first KB (once per file, cached by mtime+size); Excel/parquet use the project's python
-- once, in the background. No AI, no process while typing text files.
local py = require "utils.python"

local M = {}
local Source = {}
Source.__index = Source

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local EXT = {
  csv = { csv = true, tsv = true, txt = true, dat = true, gz = true, zip = true, parquet = true, feather = true },
  table = { csv = true, tsv = true, txt = true, dat = true, gz = true, zip = true },
  excel = { xlsx = true, xls = true, xlsm = true, xlsb = true, ods = true },
  json = { json = true, jsonl = true, ndjson = true },
  parquet = { parquet = true, pq = true },
  feather = { feather = true, arrow = true },
  html = { html = true, htm = true },
  hdf = { h5 = true, hdf = true },
  sql = { db = true, sqlite = true, sqlite3 = true },
}

local BINARY = {
  xlsx = true,
  xls = true,
  xlsm = true,
  xlsb = true,
  ods = true,
  parquet = true,
  feather = true,
  arrow = true,
  h5 = true,
  hdf = true,
}

local function settings()
  return (require("core.settings").python or {}).data or {}
end

local function empty()
  return { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
end

---@param path string
---@return string
local function extension(path)
  local e = path:lower():match "%.([%w]+)$" or ""
  if e == "gz" or e == "zip" then
    return path:lower():match("%.([%w]+)%." .. e .. "$") or e
  end
  return e
end

local function human(n)
  if n < 1024 then
    return n .. " B"
  end
  if n < 1048576 then
    return math.floor(n / 1024) .. " KB"
  end
  return string.format("%.1f MB", n / 1048576)
end

-- ── string / call detection (pure) ────────────────────────────────────────────

--- Is the cursor inside an unclosed single/double quoted string? Returns its 1-based start column.
---@param before string text of the line before the cursor
---@return boolean, integer?
function M.string_context(before)
  local quote, start, i = nil, nil, 1
  while i <= #before do
    local c = before:sub(i, i)
    if quote then
      if c == "\\" then
        i = i + 2
      else
        if c == quote then
          quote, start = nil, nil
        end
        i = i + 1
      end
    else
      if c == '"' or c == "'" then
        quote, start = c, i
      end
      i = i + 1
    end
  end
  return quote ~= nil, start
end

--- Which reader call is the string an argument of?
---@param prefix string text before the opening quote
---@return string?
local function reader_of(prefix)
  local reader = prefix:match "read_([%w_]+)%s*%([^%)]*$" or prefix:match "scan_([%w_]+)%s*%([^%)]*$"
  if reader then
    return reader
  end
  if prefix:match "[%s%(%.]open%s*%([^%)]*$" or prefix:match "Path%s*%([^%)]*$" then
    return "any"
  end
end

--- `df["total…`, `df.loc[:, "total…`, `df.tot…`
---@param before string
---@return string?, string?, string?
local function column_context(before)
  local var = before:match "([%w_]+)%s*%[%s*[\"'][^\"']*$"
  if var then
    return var, before:match "[\"']([^\"']*)$" or "", "index"
  end
  var = before:match "([%w_]+)%.loc%[[^%]]-[:\"'][^\"']*$"
  if var then
    return var, before:match "[\"']([^\"']*)$" or "", "index"
  end
  var = before:match "([%w_]+)%.$"
  if var then
    return var, "", "attr"
  end
end

-- ── pure file parsers ─────────────────────────────────────────────────────────

local function split_delimited(line, sep)
  local fields, field, quoted = {}, {}, false
  local i = 1
  while i <= #line do
    local c = line:sub(i, i)
    if c == '"' then
      if quoted and line:sub(i + 1, i + 1) == '"' then
        field[#field + 1] = '"'
        i = i + 2
      else
        quoted = not quoted
        i = i + 1
      end
    elseif c == sep and not quoted then
      fields[#fields + 1] = table.concat(field)
      field = {}
      i = i + 1
    else
      field[#field + 1] = c
      i = i + 1
    end
  end
  fields[#fields + 1] = table.concat(field)
  return fields
end

local function first_line(text)
  return (text:match "^([^\r\n]*)" or ""):gsub("^\239\187\191", "")
end

---@param line string
---@return string, integer
function M.separator(line)
  local best, bestn = ",", 0
  for _, sep in ipairs { ",", "\t", ";", "|" } do
    local n, quoted = 0, false
    for i = 1, #line do
      local c = line:sub(i, i)
      if c == '"' then
        quoted = not quoted
      elseif c == sep and not quoted then
        n = n + 1
      end
    end
    if n > bestn then
      best, bestn = sep, n
    end
  end
  return best, bestn
end

---@param text string
---@param sep string?
---@return string[]
function M.columns_delimited(text, sep)
  local line = first_line(text)
  sep = sep or M.separator(line)
  local cols = split_delimited(line, sep)
  for i, col in ipairs(cols) do
    cols[i] = vim.trim(col):gsub("^[\"']", ""):gsub("[\"']$", "")
  end
  return cols
end

--- Keys of the first object: works for `{...}`, `[{...}, ...]` and JSON lines.
---@param text string
---@return string[]
function M.columns_json(text)
  local start = text:find("{", 1, true)
  if not start then
    return {}
  end
  local keys, depth, quoted, escaped, expect, buf = {}, 0, false, false, false, nil
  for i = start, #text do
    local c = text:sub(i, i)
    if quoted then
      if escaped then
        escaped = false
      elseif c == "\\" then
        escaped = true
      elseif c == '"' then
        quoted = false
        if expect and depth == 1 and buf then
          keys[#keys + 1] = buf
          buf, expect = nil, false
        end
      elseif expect then
        buf = (buf or "") .. c
      end
    else
      if c == '"' then
        quoted, buf = true, ""
      elseif c == "{" then
        depth = depth + 1
        if depth == 1 then
          expect = true
        end
      elseif c == "}" then
        depth = depth - 1
        if depth == 0 then
          break
        end
      elseif c == "[" then
        depth = depth + 1
      elseif c == "]" then
        depth = depth - 1
      elseif c == "," and depth == 1 then
        expect = true
      end
    end
  end
  return keys
end

--- Columns of a `SELECT a, b AS c FROM …` query (read_sql's first argument).
---@param query string
---@return string[]
function M.columns_sql(query)
  local lower = query:lower()
  local start = lower:find "select%s"
  local finish = start and lower:find("%sfrom%s", start + 6)
  if not start or not finish then
    return {}
  end
  local list = query:sub(start + 6, finish - 1)
  if vim.trim(list) == "*" then
    return {}
  end
  local cols = {}
  for _, part in ipairs(vim.split(list, ",")) do
    -- `total AS amount` → amount; `orders.total` → total; `total` → total
    local col = vim.trim(part):match "as%s+([%w_]+)%s*$" or vim.trim(part):match '([%w_%."`]+)%s*$'
    if col and col ~= "*" then
      cols[#cols + 1] = col:gsub('["`]', ""):match "([%w_]+)$" or col
    end
  end
  return cols
end

---@param text string
---@return string[]
function M.columns_markdown(text)
  local lines = vim.split(text, "\n")
  for i = 1, #lines - 1 do
    if lines[i]:find("|", 1, true) and lines[i + 1]:match "^%s*|?%s*:?%-" then
      local cols = vim.split(lines[i]:gsub("^%s*|", ""):gsub("|%s*$", ""), "|")
      for j, col in ipairs(cols) do
        cols[j] = vim.trim(col)
      end
      return cols
    end
  end
  return {}
end

local function guess(v)
  if v:match "^%-?%d+$" then
    return "int"
  end
  if v:match "^%-?%d+%.%d+" then
    return "float"
  end
  if v:match "^[Tt]rue$" or v:match "^[Ff]alse$" then
    return "bool"
  end
  if v:match "^%d%d%d%d%-%d%d%-%d%d" then
    return "date"
  end
  return "str"
end

---@param text string
---@param sep string
---@param cols string[]
---@return table<string, string>
local function sample_types(text, sep, cols)
  local lines = vim.split(text, "\n")
  local types = {}
  for i = 2, math.min(#lines, 8) do
    if lines[i] ~= "" then
      local fields = split_delimited(lines[i], sep)
      for j, value in ipairs(fields) do
        local v = vim.trim(value)
        if j <= #cols and v ~= "" and not types[cols[j]] then
          types[cols[j]] = guess(v)
        end
      end
    end
  end
  return types
end

-- ── one read per file, cached by stat ─────────────────────────────────────────

local cache, pending = {}, {}

local function binary_code(ext)
  if ext == "xlsx" or ext == "xls" or ext == "xlsm" or ext == "ods" then
    return "import json,sys,pandas as pd; d=pd.read_excel(sys.argv[1],nrows=5); print(json.dumps([str(c) for c in d.columns]))"
  end
  if ext == "parquet" or ext == "arrow" then
    return "import json,sys,pandas as pd; d=pd.read_parquet(sys.argv[1]); print(json.dumps([str(c) for c in d.columns]))"
  end
  if ext == "h5" or ext == "hdf" then
    return "import json,sys,pandas as pd; d=pd.read_hdf(sys.argv[1]); print(json.dumps([str(c) for c in d.columns]))"
  end
  return "import json,sys,pandas as pd; d=pd.read_json(sys.argv[1],lines=True); print(json.dumps([str(c) for c in d.columns]))"
end

function M.refresh()
  vim.schedule(function()
    pcall(function()
      require("blink.cmp").show()
    end)
  end)
end

--- Start a background read for a binary data file; the result is cached for later keystrokes.
---@param path string
---@param root string
local function read_binary(path, root)
  if pending[path] then
    return
  end
  pending[path] = true
  local python = py.venv_python(root) or "python3"
  vim.system({ python, "-c", binary_code(extension(path)), path }, {
    timeout = settings().python_timeout_ms or 4000,
    text = true,
  }, function(result)
    pending[path] = nil
    local text = result and result.stdout or ""
    local ok, cols = pcall(vim.json.decode, text)
    if ok and type(cols) == "table" then
      local st = vim.uv.fs_stat(path)
      cache[path] = { columns = cols, types = {}, mtime = st and st.mtime.sec, size = st and st.size }
      M.refresh()
    end
  end)
end

--- Column names (and rough types) of a data file, or nil while a binary file is being read.
---@param path string
---@return { columns: string[], types: table<string,string>, sep: string? }?
function M.columns(path)
  local st = vim.uv.fs_stat(path)
  if not st or st.type ~= "file" then
    return nil
  end
  if cache[path] and cache[path].mtime == st.mtime.sec and cache[path].size == st.size then
    return cache[path]
  end
  local ext = extension(path)
  if BINARY[ext] then
    read_binary(path, py.root(vim.fs.dirname(path)))
    return nil
  end
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read(math.min(settings().sample_bytes or 16384, st.size)) or ""
  file:close()
  local cols, types, sep = {}, {}, nil
  if ext == "json" or ext == "jsonl" or ext == "ndjson" then
    cols = M.columns_json(text)
  elseif ext == "md" or ext == "markdown" then
    cols = M.columns_markdown(text)
  elseif ext ~= "" then
    sep = ext == "tsv" and "\t" or M.separator(first_line(text))
    if sep ~= "\t" and select(2, M.separator(first_line(text))) == 0 then
      sep = nil -- prose with no delimiter: no invented column
    end
    if sep then
      cols = M.columns_delimited(text, sep)
      types = sample_types(text, sep, cols)
    end
  end
  local clean, seen = {}, {}
  for _, col in ipairs(cols) do
    if col ~= "" and not seen[col] then
      seen[col] = true
      clean[#clean + 1] = col
      if #clean >= (settings().max_columns or 200) then
        break
      end
    end
  end
  local result = { columns = clean, types = types, sep = sep, mtime = st.mtime.sec, size = st.size }
  cache[path] = result
  return result
end

--- Forget a cached file (or all of them) after the data changed on disk
function M.reset(path)
  if path then
    cache[path] = nil
  else
    cache, pending = {}, {}
  end
end

-- ── assignments and paths ─────────────────────────────────────────────────────

local function resolve_path(raw, bufname)
  if raw == "" then
    return
  end
  if raw:sub(1, 1) == "~" then
    return vim.fn.expand(raw)
  end
  if raw:sub(1, 1) == "/" then
    return raw
  end
  local dir = vim.fs.dirname(bufname)
  local root = py.root(dir)
  for _, candidate in ipairs { raw, root .. "/" .. raw, dir .. "/" .. raw, root .. "/data/" .. raw } do
    if vim.uv.fs_stat(candidate) then
      return vim.fn.resolve(candidate)
    end
  end
end

--- Every `df = <reader>("file")` above the cursor, by variable name.
---@param buf integer
---@param upto integer 1-based row (exclusive)
---@return table<string, { reader: string, path: string }>
function M.assignments(buf, upto)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, upto, false)
  local bufname = vim.api.nvim_buf_get_name(buf)
  local out = {}
  for i, line in ipairs(lines) do
    local var = line:match "^%s*([%w_]+)%s*=%s*"
    if var then
      local chunk = table.concat({ line, lines[i + 1] or "", lines[i + 2] or "", lines[i + 3] or "" }, " ")
      local reader, path = chunk:match "read_([%w_]+)%s*%([^%)%\"']*[\"']([^\"']+)[\"']"
      if not reader then
        reader, path = chunk:match "scan_([%w_]+)%s*%([^%)%\"']*[\"']([^\"']+)[\"']"
      end
      if reader and path then
        if reader == "sql" and path:lower():match "^%s*select%s" then
          out[var] = { reader = reader, query = path }
        else
          local abs = resolve_path(path, bufname)
          if abs then
            out[var] = { reader = reader, path = abs }
          end
        end
      end
    end
  end
  return out
end

local function allowed(ext, reader)
  local set = EXT[reader]
  return set == nil or set[ext] == true
end

--- File items for a path typed inside a reader call.
---@param ctx blink.cmp.Context
---@param raw string text after the opening quote
---@param reader string
---@param qpos integer 1-based column of the opening quote
---@return table[]
function M.path_items(ctx, raw, reader, qpos)
  local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
  local dir, part = raw:match "^(.*/)" or "", raw
  if dir ~= "" then
    part = raw:sub(#dir + 1)
  end
  local root = py.root(vim.fs.dirname(bufname))
  local bufdir = vim.fs.dirname(bufname)
  local roots = {}
  if dir ~= "" then
    -- The folder is already typed: look exactly there (relative to the project or the buffer) and keep it in the
    -- inserted text, so accepting `data/sa` never turns into just `sales.csv`.
    if raw:sub(1, 2) == "~/" then
      roots = { vim.fn.expand "~" .. "/" .. dir:sub(3) }
    elseif raw:sub(1, 1) == "/" then
      roots = { dir }
    else
      roots = { root .. "/" .. dir, bufdir .. "/" .. dir }
    end
  else
    for _, r in ipairs(settings().roots or { "data", "datasets", "" }) do
      roots[#roots + 1] = r == "" and root or root .. "/" .. r
    end
    roots[#roots + 1] = bufdir
  end
  local range = {
    start = { line = ctx.cursor[1] - 1, character = qpos },
    ["end"] = { line = ctx.cursor[1] - 1, character = ctx.cursor[2] },
  }
  local items, seen = {}, {}
  for _, basedir in ipairs(roots) do
    local handle = vim.uv.fs_scandir(basedir)
    if handle then
      while true do
        local name, kind = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        if name:sub(1, 1) ~= "." and vim.startswith(name, part) then
          local e = extension(name)
          local prefix = dir
          -- with no typed folder, a file found in `data/` needs the folder in the inserted path
          if prefix == "" then
            local rel = vim.fs.relpath(root, basedir)
            if rel and rel ~= "" and rel ~= "." then
              prefix = rel .. "/"
            end
          end
          local insert = prefix .. name .. (kind == "directory" and "/" or "")
          if (kind == "directory" or allowed(e, reader)) and not seen[insert] then
            seen[insert] = true
            local full = basedir .. "/" .. name
            local st = vim.uv.fs_stat(full)
            local desc = kind == "directory" and "folder"
              or ((st and human(st.size) or "") .. (e ~= "" and " · " .. e or ""))
            items[#items + 1] = {
              label = insert,
              labelDetails = { description = desc },
              kind = kind == "directory" and KIND.Folder or KIND.File,
              insertTextFormat = FORMAT.PlainText,
              textEdit = { newText = insert, range = range },
              sortText = (kind == "directory" and "1" or "2") .. insert:lower(),
              data = { path = full, file = kind == "file" },
            }
          end
        end
      end
    end
  end
  return items
end

---@param item table
---@param callback fun(item: table)
function M.resolve(item, callback)
  local resolved = vim.deepcopy(item)
  local path = item.data and item.data.path
  if path and item.data.file then
    local file = io.open(path, "rb")
    if file then
      local text = file:read(300) or ""
      file:close()
      local e = extension(path)
      resolved.documentation = { kind = "markdown", value = "```" .. e .. "\n" .. text .. "\n```" }
    end
  elseif item.data and item.data.columns then
    local data = item.data.path and M.columns(item.data.path) or nil
    local col = item.label
    local kind = data and data.types and data.types[col]
    local origin = item.data.path and (" · " .. vim.fn.fnamemodify(item.data.path, ":t")) or ""
    resolved.documentation = {
      kind = "markdown",
      value = "`" .. col .. "`" .. (kind and " · " .. kind or "") .. origin,
    }
  end
  callback(resolved)
end

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "python"
end

-- `/` must reopen the menu right after `data/` (with an empty filename), and `"`/`'` at the start of a reader call.
function Source:get_trigger_characters()
  return { "/", '"', "'", ".", "\\" }
end

function Source:resolve(item, callback)
  M.resolve(item, callback)
end

function Source:execute(ctx, item, callback, default_implementation)
  default_implementation()
  callback()
end

---@param ctx blink.cmp.Context
---@param callback fun(response: table)
function Source:get_completions(ctx, callback)
  local cfg = settings()
  if cfg.enabled == false then
    return callback(empty())
  end
  local before = ctx.line:sub(1, ctx.cursor[2])

  -- 1) columns of an assigned data file
  local var, part = column_context(before)
  if var then
    local assignment = M.assignments(ctx.bufnr, ctx.cursor[1])[var]
    if assignment then
      local source = assignment.path and vim.fn.fnamemodify(assignment.path, ":t") or "query"
      local data
      if assignment.query then
        data = { columns = M.columns_sql(assignment.query), types = {} }
      else
        data = M.columns(assignment.path)
      end
      if not data then
        return callback(empty()) -- binary: read_binary scheduled the refresh
      end
      local range = {
        start = { line = ctx.cursor[1] - 1, character = math.max(ctx.cursor[2] - #part, 0) },
        ["end"] = { line = ctx.cursor[1] - 1, character = ctx.cursor[2] },
      }
      local items = {}
      for _, col in ipairs(data.columns) do
        if vim.startswith(col:lower(), part:lower()) then
          local kind = data.types[col]
          items[#items + 1] = {
            label = col,
            labelDetails = { description = (kind or "column") .. " · " .. source },
            kind = kind == "int" and KIND.Number
              or kind == "float" and KIND.Number
              or kind == "bool" and KIND.Boolean
              or kind == "date" and KIND.Event
              or KIND.Field,
            insertTextFormat = FORMAT.PlainText,
            textEdit = { newText = col, range = range },
            sortText = "1" .. col:lower(),
            data = { path = assignment.path, columns = true },
          }
        end
      end
      return callback { is_incomplete_forward = false, is_incomplete_backward = false, items = items }
    end
  end

  -- 2) paths inside a reader call
  local inside, qpos = M.string_context(before)
  if inside and qpos then
    local reader = reader_of(before:sub(1, qpos - 1))
    if reader then
      local raw = before:sub(qpos + 1)
      return callback {
        is_incomplete_forward = false,
        is_incomplete_backward = false,
        items = M.path_items(ctx, raw, reader, qpos),
      }
    end
  end
  callback(empty())
end

return M
