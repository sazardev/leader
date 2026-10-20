-- ── What the update check remembers ──────────────────────────────────────────
-- stdpath("state")/update.json: when it last looked, what it found, the changelog it fetched, the version the person
-- chose to skip and the one already announced (so the notification comes once per version, not every start).
local M = {}

M.FILE = vim.fn.stdpath "state" .. "/update.json"

local data

---@return table
function M.get()
  if data then
    return data
  end
  data = {}
  local f = io.open(M.FILE)
  if f then
    local ok, decoded = pcall(vim.json.decode, f:read "*a")
    f:close()
    if ok and type(decoded) == "table" and not vim.islist(decoded) then
      data = decoded
      for k, v in pairs(data) do
        if v == vim.NIL then
          data[k] = nil -- a null written by an older version
        end
      end
    end
  end
  return data
end

---@param patch table
function M.set(patch)
  local d = M.get()
  for k, v in pairs(patch) do
    if v == vim.NIL then
      d[k] = nil -- vim.NIL in a patch means "forget it" (never `v == NIL and nil or v`: nil is falsy)
    else
      d[k] = v
    end
  end
  vim.fn.mkdir(vim.fs.dirname(M.FILE), "p")
  local f = io.open(M.FILE, "w")
  if f then
    f:write(vim.json.encode(d))
    f:close()
  end
end

--- Tests: forget what was read.
function M.reset()
  data = nil
end

return M
