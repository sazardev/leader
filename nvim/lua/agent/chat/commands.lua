-- ── Chat commands (the `/` selector) ────────────────────────────────────────
-- Name → description and the fuzzy filter. Pure; the caller decides what each
-- command does (chat/init.lua).
local M = {}

M.ALL = {
  new = "new session",
  model = "model",
  effort = "effort",
  clear = "clear",
  adr = "ADR",
  export = "copy",
  full = "full screen",
  mini = "mini panel",
  collapse = "collapse",
  help = "help",
}

--- Ordered by usefulness: the first row is the most common action.
M.ORDER = { "new", "model", "effort", "clear", "adr", "export", "full", "mini", "collapse", "help" }

---@param name string
---@return boolean
function M.has(name)
  return M.ALL[name] ~= nil
end

---@param query string?
---@return string[]
function M.filter(query)
  query = (query or ""):lower()
  local out = {}
  for _, name in ipairs(M.ORDER) do
    if name:lower():find(query, 1, true) == 1 then
      out[#out + 1] = name
    end
  end
  return out
end

---@param query string?
---@return table[] { value, desc }
function M.candidates(query)
  local out = {}
  for _, name in ipairs(M.filter(query)) do
    out[#out + 1] = { value = name, desc = M.ALL[name] or "" }
  end
  return out
end

return M
