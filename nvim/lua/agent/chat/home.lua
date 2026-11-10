-- ── Chat history home (pure) ─────────────────────────────────────────────────
-- The screen the chat opens on when this project already has conversations:
-- a compact "New chat" row followed by the project's sessions, newest first.
-- Returns lines/marks/ranges exactly like render.lua, so window.lua only paints.
-- No editor calls: the display root and the clock come in as arguments.
local M = {}

--- Human age of a timestamp: now · 5m · 3h · 2d · 1w · 2026-01-31.
---@param ts integer?
---@param now integer?
---@return string
function M.relative_time(ts, now)
  if not ts or ts <= 0 then
    return "just now"
  end
  local seconds = math.max(0, (now or os.time()) - ts)
  if seconds < 60 then
    return "now"
  end
  if seconds < 3600 then
    return ("%dm"):format(math.floor(seconds / 60))
  end
  if seconds < 86400 then
    return ("%dh"):format(math.floor(seconds / 3600))
  end
  if seconds < 86400 * 7 then
    return ("%dd"):format(math.floor(seconds / 86400))
  end
  if seconds < 86400 * 30 then
    return ("%dw"):format(math.floor(seconds / 604800))
  end
  return os.date("%Y-%m-%d", ts)
end

--- Compact one-line title: no newlines, markdown markers or control characters.
---@param title string?
---@return string
function M.title(title)
  local text = tostring(title or "")
  for line in text:gmatch "[^\n]+" do
    line =
      line:gsub("\27%[[%d;?]*[ -/]*[@-~]", ""):gsub("^%s*#*%s*", ""):gsub("^%s*[-*+]%s+", ""):gsub("^%s*>`?%s*", "")
    line = line:gsub("`", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" then
      return #line > 62 and (line:sub(1, 62) .. "…") or line
    end
  end
  return "Untitled chat"
end

--- Metadata line of a session: age · turns · model.
---@param session table
---@param now integer?
---@return string
function M.meta(session, now)
  local bits = { M.relative_time(session.updated, now) }
  if session.turns and session.turns > 0 then
    bits[#bits + 1] = ("%d turn%s"):format(session.turns, session.turns == 1 and "" or "s")
  else
    local count = #(session.messages or {})
    bits[#bits + 1] = ("%d message%s"):format(count, count == 1 and "" or "s")
  end
  if session.model and session.model ~= "" then
    bits[#bits + 1] = (session.backend and (session.backend .. "/") or "") .. session.model
  elseif session.backend and session.backend ~= "" then
    bits[#bits + 1] = session.backend
  end
  return table.concat(bits, " · ")
end

--- Row (1 = New chat, 2.. = sessions) under a transcript line.
---@param ranges table[]
---@param line integer
---@return integer?
function M.row_at(ranges, line)
  for _, r in ipairs(ranges or {}) do
    if line >= r.first and line <= r.last then
      return r.row
    end
  end
  return nil
end

--- Render the home. `home` = { sessions, root, display_root, sel, profile }.
--- marks: render.lua shape. ranges: { first, last, row, kind, session? }.
---@param home table
---@param opts { now?: integer, total?: integer }?
---@return string[] lines, table[] marks, table[] ranges
function M.lines(home, opts)
  opts = opts or {}
  local now = opts.now or os.time()
  local sessions = home.sessions or {}
  local selected = math.max(1, math.min(home.sel or 1, #sessions + 1))
  local lines, marks, ranges = {}, {}, {}

  local function add(text, hl, extra)
    lines[#lines + 1] = text
    local mark = { line = #lines, hl = hl }
    for key, value in pairs(extra or {}) do
      mark[key] = value
    end
    marks[#marks + 1] = mark
    return #lines
  end

  add("◆ Leader Chat", "ChatHeader", { eol = true })
  add("  Recent chats", "ChatHomeTitle")
  local profile = require("agent.chat.profiles").get(home.profile)
  add(
    ("  %s · %d chat%s · %s"):format(
      home.display_root or "this project",
      #sessions,
      #sessions == 1 and "" or "s",
      profile.label
    ),
    "ChatMeta"
  )
  add ""

  local first = add("  ✚  New chat", selected == 1 and "ChatHomeSel" or "ChatHomeNew", {
    eol = selected == 1,
    spans = selected == 1 and nil or { { 2, 3, "ChatHomeIcon" } },
  })
  ranges[#ranges + 1] = { first = first, last = first, row = 1, kind = "new" }
  add ""

  if #sessions == 0 then
    add("  No chats in this project yet.", "ChatHomeEmpty")
    add("  Type below to start the first one.", "ChatHomeHint")
  else
    for i, session in ipairs(sessions) do
      local row = i + 1
      local is_selected = row == selected
      local title_hl = is_selected and "ChatHomeSel" or "ChatHomeRow"
      local meta_hl = is_selected and "ChatHomeSelMeta" or "ChatHomeMeta"
      local title_line = add("  ❯  " .. M.title(session.title), title_hl, {
        eol = is_selected,
        spans = is_selected and nil or { { 2, 3, "ChatHomeIcon" } },
      })
      local meta_line = add("     " .. M.meta(session, now), meta_hl, { eol = is_selected })
      ranges[#ranges + 1] = {
        first = title_line,
        last = meta_line,
        row = row,
        kind = "session",
        session = session,
      }
    end
  end

  add ""
  add("  ↑↓ select · ⏎ open · Ctrl-N new · Esc: n new / D delete", "ChatHomeHint")
  return lines, marks, ranges
end

return M
