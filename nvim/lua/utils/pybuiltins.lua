-- ── Python builtins and keywords (blink source, 0 tokens) ────────────────────
-- basedpyright takes ~0.7–0.9 s to answer `pri` at a NEW position (it caches completions per position and every
-- keystroke invalidates the old one). The words written most often — `print`, `len`, `for`, `if`… — are fixed, so offer
-- them locally and instantly. The LSP items arrive alongside them later. No process, no files, no state.
local pydata = require "utils.pydata"

local M = {}
local KIND = vim.lsp.protocol.CompletionItemKind
local Source = {}
Source.__index = Source

local KEYWORDS = {
  "and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del", "elif", "else",
  "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "match", "None",
  "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield",
}

local BUILTINS = {
  "abs", "aiter", "all", "anext", "any", "ascii", "bin", "bool", "breakpoint", "bytearray", "bytes", "callable",
  "chr", "classmethod", "compile", "complex", "delattr", "dict", "dir", "divmod", "enumerate", "eval", "exec",
  "Exception", "filter", "float", "format", "frozenset", "getattr", "globals", "hasattr", "hash", "help", "hex",
  "id", "IndexError", "input", "int", "isinstance", "issubclass", "iter", "KeyError", "len", "list", "locals",
  "map", "max", "memoryview", "min", "next", "object", "oct", "open", "ord", "pow", "print", "property", "range",
  "repr", "reversed", "round", "RuntimeError", "set", "setattr", "slice", "sorted", "staticmethod", "str", "sum",
  "super", "tuple", "type", "TypeError", "ValueError", "vars", "zip",
}

--- All the words this source offers, keywords first (pure, stable order).
---@return string[]
function M.words()
  local out = {}
  for _, word in ipairs(KEYWORDS) do
    out[#out + 1] = word
  end
  for _, word in ipairs(BUILTINS) do
    out[#out + 1] = word
  end
  return out
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

---@param ctx blink.cmp.Context
---@param callback fun(response: table)
function Source:get_completions(ctx, callback)
  local before = ctx.line:sub(1, ctx.cursor[2])
  local word = before:match "[%w_]*$" or ""
  if #word < 2 or before:sub(-#word - 1, -#word - 1) == "." then
    return callback(empty())
  end
  if pydata.string_context(before) then -- paths, columns: pydata owns those
    return callback(empty())
  end
  local line, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local range = {
    start = { line = line, character = math.max(col - #word, 0) },
    ["end"] = { line = line, character = col },
  }
  local items = {}
  for _, name in ipairs(KEYWORDS) do
    if name:sub(1, #word):lower() == word:lower() then
      items[#items + 1] = {
        label = name,
        kind = KIND.Keyword,
        detail = "keyword",
        textEdit = { range = range, newText = name },
      }
    end
  end
  for _, name in ipairs(BUILTINS) do
    if name:sub(1, #word):lower() == word:lower() then
      items[#items + 1] = {
        label = name,
        kind = KIND.Function,
        detail = "builtin",
        textEdit = { range = range, newText = name },
      }
    end
  end
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return M
