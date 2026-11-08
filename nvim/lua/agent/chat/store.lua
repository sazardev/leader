-- Chat persistence: sessions on disk, per project.
-- stdpath("state")/agent-chat.json: { sessions = { [id] = session }, last = id, by_root = { [root] = id } }
-- A session's transcript is kept (so history/ADR work after a restart) but the
-- exact prompt is not stored again: runs already records prompts in agent-history.jsonl.
local M = {}

local PATH = vim.fn.stdpath "state" .. "/agent-chat.json"
local MAX_MESSAGES = 200 -- transcript kept per session; older turns stay in agent-history

---@type table?
local cache

local function read()
  if cache then
    return cache
  end
  cache = { sessions = {}, by_root = {} }
  local f = io.open(PATH, "r")
  if f then
    local raw = f:read "*a"
    f:close()
    local ok, data = pcall(vim.json.decode, raw)
    if ok and type(data) == "table" then
      cache = data
      cache.sessions = cache.sessions or {}
      cache.by_root = cache.by_root or {}
    end
  end
  return cache
end

function M.save()
  if not require("core.settings").agent.chat.autosave then
    return
  end
  local data = read()
  local obj = vim.deepcopy(data)
  for _, s in pairs(obj.sessions) do
    -- keep the transcript short; the full run log lives in agent-history.jsonl
    if s.messages and #s.messages > MAX_MESSAGES then
      local kept = {}
      for i = #s.messages - MAX_MESSAGES + 1, #s.messages do
        kept[#kept + 1] = s.messages[i]
      end
      s.messages = kept
    end
  end
  vim.fn.mkdir(vim.fn.fnamemodify(PATH, ":h"), "p")
  local f = io.open(PATH, "w")
  if f then
    f:write(vim.json.encode(obj))
    f:close()
  end
end

---@param s table
function M.put(s)
  local data = read()
  data.sessions[s.id] = {
    id = s.id,
    title = s.title,
    root = s.root,
    backend = s.backend,
    model = s.model,
    effort = s.effort,
    messages = s.messages,
    tokens_in = s.tokens_in,
    tokens_out = s.tokens_out,
    cost = s.cost,
    turns = s.turns,
    created = s.created,
    updated = s.updated,
  }
  data.by_root[s.root] = s.id
  data.last = s.id
  M.save()
end

---@param id string
---@return table?
function M.get(id)
  local s = read().sessions[id]
  if not s then
    return nil
  end
  return require("agent.chat.session").new(s)
end

---@param root string
---@return table?
function M.last_for_root(root)
  local data = read()
  local id = data.by_root[root] or data.last
  return id and M.get(id) or nil
end

---@return table[] newest first
function M.list()
  local out = vim.tbl_values(read().sessions)
  table.sort(out, function(a, b)
    return (a.updated or 0) > (b.updated or 0)
  end)
  return out
end

---@param id string
function M.remove(id)
  local data = read()
  data.sessions[id] = nil
  M.save()
end

function M.clear()
  cache = nil
  pcall(os.remove, PATH)
  cache = { sessions = {}, by_root = {} }
end

--- Test hook: forget the in-memory cache (scripts point XDG_STATE_HOME at a temp dir).
function M._reset()
  cache = nil
end

return M
