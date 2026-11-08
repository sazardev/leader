-- ── Env: pure parsing of .env files ────────────────────────────────────────
-- 0 tokens, no side effects. `parse` reads KEY=value lines (export prefix, quotes,
-- comments, blank lines), `keys` returns them in file order, `diff` compares an
-- example against a real file (missing / extra / empty). Tested in scripts/test-env.lua.
local M = {}

---@class EnvEntry
---@field key string
---@field value string
---@field line integer

---@ Parse .env text into entries (file order kept)
---@param text string
---@return EnvEntry[]
function M.parse(text)
  local out = {}
  local lines = vim.split(text or "", "\n", { plain = true })
  for i, raw in ipairs(lines) do
    local line = raw:gsub("\r$", "")
    local stripped = vim.trim(line)
    if stripped == "" or stripped:sub(1, 1) == "#" then
      -- skip
    else
      local k, v = line:match "^%s*export%s+([%w_%.]+)%s*=%s*(.-)%s*$"
      if not k then
        k, v = line:match "^%s*([%w_%.]+)%s*=%s*(.-)%s*$"
      end
      if k and not line:match "^%s*#" then
        local quoted = v:match '^"(.*)"$' or v:match "^'(.*)'$"
        local value = quoted or (v:gsub("%s+#.*$", ""))
        out[#out + 1] = { key = k, value = value or "", line = i }
      end
    end
  end
  return out
end

---@ Keys in file order (no duplicates)
---@param entries EnvEntry[]
---@return string[]
function M.keys(entries)
  local seen, out = {}, {}
  for _, e in ipairs(entries) do
    if not seen[e.key] then
      seen[e.key] = true
      out[#out + 1] = e.key
    end
  end
  return out
end

---@ Compare example keys against a real file's entries
---@param example_entries EnvEntry[]
---@param real_entries EnvEntry[]
---@return { missing: string[], extra: string[], empty: string[] }
function M.diff(example_entries, real_entries)
  local ex_keys = M.keys(example_entries)
  local ex_set = {}
  for _, k in ipairs(ex_keys) do
    ex_set[k] = true
  end
  local real_set, empty = {}, {}
  for _, e in ipairs(real_entries) do
    real_set[e.key] = true
    if vim.trim(e.value or "") == "" then
      empty[#empty + 1] = e.key
    end
  end
  local missing, extra = {}, {}
  for _, k in ipairs(ex_keys) do
    if not real_set[k] then
      missing[#missing + 1] = k
    end
  end
  for _, e in ipairs(real_entries) do
    if not ex_set[e.key] then
      extra[#extra + 1] = e.key
    end
  end
  -- dedupe extra preserving order
  local seen, dedup = {}, {}
  for _, k in ipairs(extra) do
    if not seen[k] then
      seen[k] = true
      dedup[#dedup + 1] = k
    end
  end
  return { missing = missing, extra = dedup, empty = empty }
end

---@ Is this a file name an env file? (.env, .env.local, .env.dev…)
---@param name string
---@return boolean
function M.is_env(name)
  return vim.fs.basename(name) == ".env" or vim.fs.basename(name):match "^%.env%." ~= nil
end

---@ Every .env* file under `root` (non-recursive, sorted)
---@param root string
---@return string[]
function M.list_files(root)
  local out = {}
  local iter = vim.fs.dir(root)
  if not iter then
    return out
  end
  for name, kind in vim.fs.dir(root) do
    if kind == "file" and M.is_env(name) then
      out[#out + 1] = root .. "/" .. name
    end
  end
  table.sort(out)
  return out
end

return M
