-- ── Errors out of a tool's output ────────────────────────────────────────────
-- `go build`, `tsc`, `cargo`, `python`, `javac`, linters: they all print `file:line:col: message` in some dress. Neovim
-- already knows those dresses (the `errorformat` of quickfix), so nothing here parses text by hand: the output goes through
-- `getqflist({ lines, efm })` once per known format and the format that explains the most lines wins. 0 tokens.
local M = {}

---@class AgentToolError
---@field file string     absolute path
---@field lnum integer
---@field col integer
---@field text string
---@field severity "error"|"warn"
---@field tool string     which format matched

--- One errorformat per tool. Order matters only for ties (the generic one goes last)
---@type { name: string, efm: string }[]
M.FORMATS = {
  { name = "go", efm = "%-G# %.%#,%f:%l:%c: %m,%f:%l: %m" },
  {
    name = "tsc",
    efm = "%f(%l\\,%c): %trror TS%n: %m,%f(%l\\,%c): %tarning TS%n: %m,%f:%l:%c - %trror TS%n: %m,%f:%l:%c - %tarning TS%n: %m",
  },
  { name = "cargo", efm = "%Eerror[E%n]: %m,%Eerror: %m,%Wwarning: %m,%C%*[ ]--> %f:%l:%c,%-G%.%#" },
  {
    name = "python",
    efm = '%A  File "%f"\\, line %l\\, in %o,%A  File "%f"\\, line %l,%C    %.%#,%Z%[A-Za-z]%\\+Error%.%#: %m',
  },
  { name = "javac", efm = "%E[ERROR] %f:[%l\\,%c] %m,%E%f:%l: error: %m,%Z%p^,%C%.%#,%-G%.%#" },
  -- `flutter analyze`: "  error • message • lib/a.dart:3:10 • code"
  {
    name = "flutter",
    efm = "%*[ ]%trror • %m • %f:%l:%c • %.%#,%tarning • %m • %f:%l:%c • %.%#,%*[ ]%tarning • %m • %f:%l:%c • %.%#,%*[ ]%tnfo • %m • %f:%l:%c • %.%#",
  },
  -- `dart analyze`: "  error - lib/a.dart:3:10 - message - code" and its `--format=machine` (absolute paths)
  {
    name = "dart",
    efm = "%*[ ]%trror - %f:%l:%c - %m,%tarning - %f:%l:%c - %m,%*[ ]%tnfo - %f:%l:%c - %m,"
      .. "%tRROR|%*[^|]|%*[^|]|%f|%l|%c|%*[^|]|%m,%tARNING|%*[^|]|%*[^|]|%f|%l|%c|%*[^|]|%m,%tNFO|%*[^|]|%*[^|]|%f|%l|%c|%*[^|]|%m",
  },
  { name = "generic", efm = "%f:%l:%c: %m,%f:%l: %m" },
}

--- Removes terminal colors and carriage returns (what a terminal buffer holds)
---@param text string
---@return string
function M.strip_ansi(text)
  return (text:gsub("\27%[[%d;?]*[%a]", ""):gsub("\27%][^\7]*\7", ""):gsub("\r", ""))
end

---@param type string?
---@return "error"|"warn"
local function severity_of(type)
  return (type == "W" or type == "w" or type == "I" or type == "i") and "warn" or "error"
end

---@param lines string[]
---@param efm string
---@return table[]
local function run_format(lines, efm)
  local ok, res = pcall(vim.fn.getqflist, { lines = lines, efm = efm })
  if not ok or type(res) ~= "table" then
    return {}
  end
  return vim.tbl_filter(function(item)
    return item.valid == 1 and item.lnum and item.lnum > 0
  end, res.items or {})
end

--- Errors in `text`. `root` makes relative paths absolute and keeps only files inside the project
---@param text string
---@param opts { root: string?, only_readable: boolean? }?
---@return AgentToolError[]
function M.parse(text, opts)
  opts = opts or {}
  local lines = vim.split(M.strip_ansi(text), "\n", { plain = true })
  local best, best_items = nil, {}
  for _, f in ipairs(M.FORMATS) do
    local items = run_format(lines, f.efm)
    if #items > #best_items then
      best, best_items = f, items
    end
  end
  local out, seen = {}, {}
  for _, item in ipairs(best_items) do
    local name = item.bufnr and item.bufnr > 0 and vim.fn.bufname(item.bufnr) or ""
    if name == "" and item.filename then
      name = item.filename
    end
    local abs = name ~= ""
        and vim.fn.fnamemodify(opts.root and not name:match "^/" and (opts.root .. "/" .. name) or name, ":p")
      or nil
    if abs and abs:sub(-1) == "/" then
      abs = nil
    end
    local inside = abs and (not opts.root or abs:find(vim.fn.fnamemodify(opts.root, ":p"), 1, true) == 1)
    local readable = abs and (opts.only_readable == false or vim.fn.filereadable(abs) == 1)
    if abs and inside and readable then
      local key = ("%s:%d:%s"):format(abs, item.lnum, item.text)
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = {
          file = abs,
          lnum = item.lnum,
          col = item.col or 0,
          text = vim.trim(item.text or ""),
          severity = severity_of(item.type),
          tool = best.name,
        }
      end
    end
  end
  return out
end

--- The errors as diagnostics (what the grouping and the diagnostics provider understand): `lnum` is 0-based
---@param errors AgentToolError[]
---@return table[]
function M.as_diagnostics(errors)
  return vim.tbl_map(function(e)
    return {
      lnum = e.lnum - 1,
      col = math.max(e.col - 1, 0),
      severity = e.severity == "warn" and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
      message = e.text,
      source = e.tool,
    }
  end, errors)
end

--- The quickfix list as errors (what `:make`, `:grep`, `:cexpr` or another plugin left there)
---@param opts { root: string? }?
---@return AgentToolError[]
function M.from_quickfix(opts)
  opts = opts or {}
  local out = {}
  for _, item in ipairs(vim.fn.getqflist()) do
    local abs = item.bufnr and item.bufnr > 0 and vim.api.nvim_buf_get_name(item.bufnr) or ""
    if item.valid == 1 and item.lnum > 0 and abs ~= "" and vim.fn.filereadable(abs) == 1 then
      out[#out + 1] = {
        file = abs,
        lnum = item.lnum,
        col = item.col or 0,
        text = vim.trim(item.text or ""),
        severity = severity_of(item.type),
        tool = "quickfix",
      }
    end
  end
  return out
end

--- Does anything in the output look like an error? (cheap check before parsing, for sources that may hold anything)
---@param text string
---@return boolean
function M.looks_like_errors(text)
  return text:find ":%d+:%d*:?%s" ~= nil or text:find "%(%d+,%d+%)" ~= nil or text:find "line %d+" ~= nil
end

return M
