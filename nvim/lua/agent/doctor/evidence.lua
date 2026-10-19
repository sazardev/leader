-- ── Evidence: what a failure left behind, made fit to read ───────────────────
-- Everything the troubleshooting agent sends (or shows) goes through here first: colors off, repeated lines folded, secrets
-- blacked out, the long middle cut so the lines around the first errors and the end survive, and the stack frames that point
-- into the project turned into code excerpts. Pure but for `code_around` (reads a file). 0 tokens.
local M = {}

--- Removes terminal colors and carriage returns
---@param text string
---@return string
function M.strip_ansi(text)
  return (text:gsub("\27%[[%d;?]*[%a]", ""):gsub("\27%][^\7]*\7", ""):gsub("\r", ""))
end

--- Colors off and consecutive identical lines folded into the first one and a count
---@param text string
---@return string
function M.clean(text)
  local out, prev, n = {}, nil, 0
  local function flush()
    if n > 0 then
      out[#out + 1] = ("[… the line above repeated %d more time%s]"):format(n, n == 1 and "" or "s")
      n = 0
    end
  end
  for line in (M.strip_ansi(text) .. "\n"):gmatch "(.-)\n" do
    if prev ~= nil and line == prev and line:match "%S" then
      n = n + 1
    else
      flush()
      out[#out + 1] = line
      prev = line
    end
  end
  flush()
  return (table.concat(out, "\n"):gsub("%s+$", ""))
end

--- What looks like a secret, replaced. Not a promise of safety (the user sees what is sent with `p`), a net for the usual spills.
local SECRETS = {}
--- `NAME<key>…: value` / `NAME<key>…= "value"`: the value goes, the name stays
---@param key string a Lua pattern (with classes for both cases)
local function assignment(key)
  SECRETS[#SECRETS + 1] =
    { "(%f[%w_][%w_%.%-]*" .. key .. "[%w_%.%-]*[\"']?%s*[=:]%s*[\"']?)[^%s\"',;]+", "%1[redacted]" }
end
assignment "[Pp][Aa][Ss][Ss][Ww]?[Oo]?[Rr]?[Dd]?"
assignment "[Ss][Ee][Cc][Rr][Ee][Tt]"
assignment "[Tt][Oo][Kk][Ee][Nn]"
assignment "[Aa][Pp][Ii][_%-]?[Kk][Ee][Yy]"
for _, r in ipairs {
  { "([Aa]uthorization:%s*)[^\n]+", "%1[redacted]" },
  { "([Bb]earer%s+)[%w%._%-~+/=]+", "%1[redacted]" },
  { "(://[^/:@%s]+:)[^@%s]+(@)", "%1[redacted]%2" }, -- user:password@host
  { "sk%-[%w_%-]+", "[redacted]" },
  { "AKIA[0-9A-Z]+", "[redacted]" },
  { "gh[pousr]_[%w]+", "[redacted]" },
  { "xox[abprs]%-[%w%-]+", "[redacted]" },
  { "%-%-%-%-%-BEGIN [%u ]*PRIVATE KEY%-%-%-%-%-.-%-%-%-%-%-END [%u ]*PRIVATE KEY%-%-%-%-%-", "[redacted private key]" },
} do
  SECRETS[#SECRETS + 1] = r
end

---@param text string
---@return string
function M.redact(text)
  for _, r in ipairs(SECRETS) do
    text = text:gsub(r[1], r[2])
  end
  return text
end

local WORDS = {
  "error",
  "fatal",
  "panic",
  "exception",
  "traceback",
  "failed",
  "failure",
  "cannot",
  "can't",
  "could not",
  "refused",
  "denied",
  "not found",
  "no such",
  "undefined",
  "unresolved",
  "enoent",
  "eaddrinuse",
  "segfault",
  "segmentation",
}

---@param line string
---@return boolean
local function interesting(line)
  local low = line:lower()
  for _, w in ipairs(WORDS) do
    if low:find(w, 1, true) then
      return true
    end
  end
  return false
end

--- Fits `text` in `max` characters keeping what explains a failure: the first lines, the lines around the first and the last
--- errors, and the end (where a build prints its verdict); what is cut says how many lines it was
---@param text string
---@param max integer
---@return string
function M.excerpt(text, max)
  if #text <= max then
    return text
  end
  local lines = vim.split(text, "\n", { plain = true })
  local n = #lines
  local hits = {}
  for i, l in ipairs(lines) do
    if interesting(l) then
      hits[#hits + 1] = i
    end
  end
  -- priority order: the end, the first errors, the last errors, the head
  local windows = { { n - 29, n } }
  for i = 1, math.min(#hits, 6) do
    windows[#windows + 1] = { hits[i] - 4, hits[i] + 6 }
  end
  for i = #hits, math.max(7, #hits - 3), -1 do
    windows[#windows + 1] = { hits[i] - 4, hits[i] + 6 }
  end
  windows[#windows + 1] = { 1, 12 }
  local keep, used = {}, 0
  for _, w in ipairs(windows) do
    local from, to = math.max(1, w[1]), math.min(n, w[2])
    local cost = 0
    for i = from, to do
      if not keep[i] then
        cost = cost + #lines[i] + 1
      end
    end
    if used + cost <= max - 80 or used == 0 then
      for i = from, to do
        keep[i] = true
      end
      used = used + cost
    end
  end
  local out, skipped = {}, 0
  for i = 1, n do
    if keep[i] then
      if skipped > 0 then
        out[#out + 1] = ("[… %d line%s omitted …]"):format(skipped, skipped == 1 and "" or "s")
        skipped = 0
      end
      out[#out + 1] = #lines[i] > 400 and (lines[i]:sub(1, 400) .. "…") or lines[i]
    else
      skipped = skipped + 1
    end
  end
  if skipped > 0 then
    out[#out + 1] = ("[… %d line%s omitted …]"):format(skipped, skipped == 1 and "" or "s")
  end
  return table.concat(out, "\n")
end

local EXT = {}
for _, e in ipairs {
  "js", "jsx", "ts", "tsx", "mjs", "cjs", "vue", "svelte", "go", "py", "rs", "java", "kt", "kts", "dart", "rb", "php", "cs",
  "swift", "c", "cc", "cpp", "h", "hpp", "lua", "ex", "exs", "sql", "yaml", "yml", "toml", "json", "mod", "gradle", "sh",
} do
  EXT[e] = true
end

local FOREIGN = {
  "/node_modules/",
  "/vendor/",
  "/.venv/",
  "/venv/",
  "/site-packages/",
  "/.cargo/",
  "/rustc/",
  "/go/pkg/mod/",
  "/usr/lib/",
  "/usr/local/lib/",
  "/.pub-cache/",
  "/.gradle/",
  "/.m2/",
}

---@param path string
---@return boolean
local function foreign(path)
  for _, f in ipairs(FOREIGN) do
    if path:find(f, 1, true) then
      return true
    end
  end
  return false
end

---@class DoctorFrame
---@field file string absolute
---@field lnum integer
---@field line string the text line it came from

--- The `file:line` places of a text that are files of the project (stack frames, compiler errors), in the order of the text
--- (a Python traceback prints the culprit last: that one goes first). `exists(abs)` says whether a path is a file.
---@param text string
---@param root string
---@param exists fun(abs: string): boolean
---@param max integer
---@return DoctorFrame[]
function M.frames(text, root, exists, max)
  local found, seen = {}, {}
  local function add(path, lnum, line)
    if foreign(path) then
      return
    end
    local abs = path:match "^/" and path or (root .. "/" .. path:gsub("^%./", ""))
    local key = abs .. ":" .. lnum
    if seen[key] or not exists(abs) then
      return
    end
    seen[key] = true
    found[#found + 1] = { file = abs, lnum = tonumber(lnum), line = vim.trim(line):sub(1, 200) }
  end
  for line in (text .. "\n"):gmatch "(.-)\n" do
    local py_path, py_line = line:match 'File "([^"]+)", line (%d+)'
    if py_path then
      add(py_path, py_line, line)
    else
      for path, ext, lnum in line:gmatch "([%w_%-%./@\\~]+%.(%a+)):(%d+)" do
        if EXT[ext] then
          add(path, lnum, line)
        end
      end
    end
  end
  if text:find("most recent call last", 1, true) then
    local rev = {}
    for i = #found, 1, -1 do
      rev[#rev + 1] = found[i]
    end
    found = rev
  end
  return vim.list_slice(found, 1, max)
end

--- The lines around `lnum` of a file with their numbers and a marker on the one that failed
---@param file string absolute
---@param lnum integer
---@param context integer lines each side
---@return string?
function M.code_around(file, lnum, context)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or #lines == 0 then
    return nil
  end
  local from, to = math.max(1, lnum - context), math.min(#lines, lnum + context)
  local out = {}
  for i = from, to do
    out[#out + 1] = ("%s%4d  %s"):format(i == lnum and ">" or " ", i, lines[i])
  end
  return table.concat(out, "\n")
end

return M
