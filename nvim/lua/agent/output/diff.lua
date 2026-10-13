-- ── Diferencias por líneas (puro) ────────────────────────────────────────────
local M = {}

---@class AgentHunk
---@field a_start integer  primera línea vieja afectada (o tras cuál se inserta si a_count == 0)
---@field a_count integer
---@field b_start integer
---@field b_count integer

--- Un bloque vacío es "", no una línea en blanco (que sería una línea fantasma en el diff)
---@param lines string[]
---@return string
local function join(lines)
  return #lines == 0 and "" or table.concat(lines, "\n") .. "\n"
end

---@param old string[]
---@param new string[]
---@return AgentHunk[]
function M.hunks(old, new)
  local diff = vim.text and vim.text.diff or vim.diff
  local indices = diff(join(old), join(new), {
    result_type = "indices",
    algorithm = "histogram",
  })
  local list = {}
  for _, h in ipairs(indices or {}) do
    list[#list + 1] = { a_start = h[1], a_count = h[2], b_start = h[3], b_count = h[4] }
  end
  return list
end

return M
