-- ── Code search: ranking (pure) ──────────────────────────────────────────────
-- "where is the order created?" → words → the symbols whose NAME, doc comment, signature or PATH talk about them.
-- No model and no vectors: identifiers are split into words (`CreateOrder`, `create_order`), lightly stemmed so
-- `created`/`creates`/`create` meet, and scored. Nothing here touches files or buffers.
local M = {}

local STOP = {}
for w in
  ([[a an and are as at be by can do does done for from how i if in is it its of on or that the this to was what where
  when which who why with find show me get all code function method]]):gmatch "%a+"
do
  STOP[w] = true
end
-- filler is dropped from the QUERY only: the words of a symbol's own name are never filtered
local SUFFIXES = { "ing", "ed", "es", "s", "e" }

---@param w string lowercase word
---@return string
function M.stem(w)
  for _, suffix in ipairs(SUFFIXES) do
    if #w > #suffix + 2 and w:sub(-#suffix) == suffix then
      return w:sub(1, -#suffix - 1)
    end
  end
  return w
end

--- Splits identifiers, paths and prose into lowercase words: `CreateOrderHTTP` → create order http
---@param text string
---@return string[]
function M.words(text)
  local out = {}
  text = text:gsub("(%l)(%u)", "%1 %2"):gsub("(%u+)(%u%l)", "%1 %2")
  for w in text:gmatch "%a[%a%d]*" do
    out[#out + 1] = w:lower()
  end
  return out
end

--- The words of a question, without filler, stemmed
---@param query string
---@return string[]
function M.query(query)
  local out = {}
  for _, w in ipairs(M.words(query)) do
    if not STOP[w] and #w > 1 then
      out[#out + 1] = M.stem(w)
    end
  end
  return out
end

--- Do two stems refer to the same thing? (equal, or one starts the other: `order`/`orders`/`ordering`)
---@param a string
---@param b string
---@return boolean exact, boolean partial
local function same(a, b)
  if a == b then
    return true, true
  end
  local short, long = (#a < #b) and a or b, (#a < #b) and b or a
  return false, #short >= 3 and long:sub(1, #short) == short
end

---@class CodeSymbol
---@field name string
---@field kind "function"|"type"
---@field path string      relative to the project
---@field line integer
---@field sig string       first line of the declaration
---@field doc string?      the comment right above it
---@field words string[]?  cached name words (stemmed)
---@field pwords string[]? cached path words (stemmed)
---@field dwords string[]? cached doc + signature words (stemmed)

local W_NAME, W_PART, W_PATH, W_DOC = 10, 5, 3, 1.5

---@param list string[]
---@return string[]
local function stems(list)
  return vim.tbl_map(M.stem, list)
end

--- Fills the word caches of a symbol (once)
---@param sym CodeSymbol
function M.prepare(sym)
  if sym.words then
    return
  end
  sym.words = stems(M.words(sym.name))
  sym.pwords = stems(M.words(sym.path))
  sym.dwords = stems(M.words((sym.doc or "") .. " " .. sym.sig))
end

local function best(word, list)
  local part = false
  for _, w in ipairs(list) do
    local exact, partial = same(word, w)
    if exact then
      return "exact"
    end
    part = part or partial
  end
  return part and "part" or nil
end

--- Score of a symbol for a query (words from `M.query`). 0 = does not match.
---@param sym CodeSymbol
---@param q string[]
---@return number
function M.score(sym, q)
  if #q == 0 then
    return 0
  end
  M.prepare(sym)
  local total, covered = 0, 0
  for _, word in ipairs(q) do
    local hit = 0
    local in_name = best(word, sym.words)
    if in_name == "exact" then
      hit = W_NAME
    elseif in_name == "part" then
      hit = W_PART
    end
    local in_path = best(word, sym.pwords)
    if in_path then
      hit = hit + (in_path == "exact" and W_PATH or W_PATH / 2)
    end
    local in_doc = best(word, sym.dwords)
    if in_doc then
      hit = hit + W_DOC
    end
    if hit > 0 then
      covered = covered + 1
      total = total + hit
    end
  end
  if covered == 0 then
    return 0
  end
  -- every word counts: a symbol that explains the whole question beats one that explains a part of it
  total = total * (0.5 + 0.5 * covered / #q)
  if sym.kind == "type" then
    total = total * 0.9
  end
  if sym.path:find "[Tt]est" or sym.path:find "[Ss]pec" or sym.path:find "mock" then
    total = total * 0.5
  end
  -- short names say what they do; very long ones are usually glue
  return total / (1 + #sym.words / 20)
end

--- The best `limit` symbols for a query, best first. An empty query lists them by path.
---@param index CodeSymbol[]
---@param query string
---@param limit integer
---@return CodeSymbol[]
function M.search(index, query, limit)
  local q = M.query(query)
  local scored = {}
  if #q == 0 then
    for i = 1, math.min(limit, #index) do
      scored[i] = { sym = index[i], score = 0 }
    end
  else
    for _, sym in ipairs(index) do
      local s = M.score(sym, q)
      if s > 0 then
        scored[#scored + 1] = { sym = sym, score = s }
      end
    end
    table.sort(scored, function(a, b)
      if a.score ~= b.score then
        return a.score > b.score
      end
      if a.sym.path ~= b.sym.path then
        return a.sym.path < b.sym.path
      end
      return a.sym.line < b.sym.line
    end)
  end
  local out = {}
  for i = 1, math.min(limit, #scored) do
    out[i] = scored[i].sym
  end
  return out
end

return M
