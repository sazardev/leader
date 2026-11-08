-- ADR from a chat: draft the decision record the session already shaped.
-- One light request; then write docs/adr/NNNN-slug.md + the index.
-- Reuses kit/adr.lua's pure render/index so both features agree on the shape.
local M = {}

--- Draft an ADR from `session` and write it. Returns (path?, err?).
---@param session table
---@param root string
---@param cb fun(path: string?, err: string?)
function M.from_session(session, root, cb)
  local transcript = {}
  for _, msg in ipairs(session.messages) do
    if msg.role == "user" or msg.role == "assistant" then
      transcript[#transcript + 1] = (msg.role == "user" and "USER: " or "LEADER: ") .. (msg.text or "")
    end
  end
  if #transcript == 0 then
    return cb(nil, "nothing to record yet")
  end
  local body = table.concat(transcript, "\n\n")
  body = require("agent.text").clip(body, 8000)

  local oneshot = require "agent.oneshot"
  oneshot.run({
    action = "chat_adr",
    tier = "light",
    system = "Draft an ADR in English, Markdown, exactly:\n# title line\n## Status\nAccepted · date\n## Context\nwhat forced it\n## Decision\n- one bullet per decision\n## Consequences\n- what follows\nOnly the ADR, no prose.",
    prompt = "<chat>\n" .. body .. "\n</chat>\nDate: " .. os.date "%Y-%m-%d",
  }, function(ok, text, usage)
    if not ok then
      return cb(nil, text or "ADR draft failed")
    end
    local adr = require "agent.kit.adr"
    local files = adr.read(root)
    local number = adr.next_number(vim.tbl_keys(files))
    -- extract title from the drafted "# ..." line if present
    local title = (text:match "^#%s*([^\n]+)") or "Chat decision"
    local entry = {
      title = title,
      date = os.date "%Y-%m-%d",
      context = "Decided in a Leader Chat session ("
        .. (session.title or "chat")
        .. ").\n\n"
        .. require("agent.text").clip(body, 1200),
      decisions = {},
    }
    -- decisions = bullets of the drafted ## Decision section
    local decision = text:match "## Decision%s*\n(.-)\n## " or ""
    for line in decision:gmatch "[^\n]+" do
      local d = line:match "^%s*[-*]%s+(.+)$"
      if d then
        entry.decisions[#entry.decisions + 1] = d
      end
    end
    if #entry.decisions == 0 then
      entry.decisions = { "See the chat transcript " .. (session.id or "") }
    end
    local dir = root .. "/" .. adr.DIR
    vim.fn.mkdir(dir, "p")
    local name = ("%04d-%s.md"):format(number, adr.slug(title))
    local path = dir .. "/" .. name
    local f = io.open(path, "w")
    if not f then
      return cb(nil, "could not write " .. path)
    end
    f:write(adr.render(number, entry))
    f:close()
    files[name] = adr.render(number, entry)
    -- rewrite the index (pure helper)
    local rows = {}
    local by = adr.superseded(files)
    for file, text in pairs(files) do
      rows[#rows + 1] = {
        file = file,
        title = text:match "^# %d+%.%s*([^\n]+)" or file,
        date = text:match "\n## Status%s*\n%s*%a+ · ([%d%-]+)" or "",
        superseded = by[tonumber(file:match "^(%d+)")],
      }
    end
    local idx = io.open(root .. "/" .. adr.INDEX, "w")
    if idx then
      idx:write(adr.index(rows))
      idx:close()
    end
    cb(path, nil, usage)
  end)
end

return M
