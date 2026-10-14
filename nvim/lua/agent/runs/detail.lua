-- ── A run, complete and readable (markdown) ──────────────────────────────────
-- It is what the history previewer shows (rendered) and what <C-y> copies: what was asked, the code that was sent (in
-- its language, so it is highlighted), what the model returned (rendered as the markdown it is), how much it cost,
-- and the raw system prompt and message.
local fmt = require "agent.runs.format"

local M = {}

--- A fence longer than any run of backticks inside `body`: the content can never close it
---@param body string
---@return string
local function fence_for(body)
  local fence = "```"
  while body:find(fence, 1, true) do
    fence = fence .. "`"
  end
  return fence
end

---@param lines string[]
---@param lang string
---@param body string
local function code(lines, lang, body)
  local fence = fence_for(body)
  lines[#lines + 1] = fence .. lang
  vim.list_extend(lines, vim.split(body, "\n", { plain = true }))
  lines[#lines + 1] = fence
end

--- The code a prompt carried: the target (what the model may change) and the code around it (read-only context)
---@param prompt string?
---@return string? target, string? around
function M.code_sent(prompt)
  if not prompt then
    return nil, nil
  end
  local target = prompt:match "<target[^>]*>\n(.-)\n?</target>"
  local around = prompt:match "<around>\n(.-)\n?</around>"
  return target, around
end

--- The model's answer as markdown: its own code blocks get highlighted. A fence left open (a cut answer) is closed so it
--- cannot swallow the sections after it.
---@param lines string[]
---@param body string
local function answer(lines, body)
  local open = false
  for _, l in ipairs(vim.split(body, "\n", { plain = true })) do
    lines[#lines + 1] = l
    if l:match "^%s*```" then
      open = not open
    end
  end
  if open then
    lines[#lines + 1] = "```"
  end
end

---@param lines string[]
---@param title string
---@param body string?
local function block(lines, title, body)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## " .. title
  lines[#lines + 1] = ""
  if not body or body == "" then
    lines[#lines + 1] = "_not stored (`settings.agent.history.store_text = false`) or empty_"
    return
  end
  code(lines, "text", body)
end

---@param run table
---@return string[]
function M.build(run)
  local u = run.usage or {}
  local rows = {
    { "when", os.date("%Y-%m-%d %H:%M:%S", run.ts) },
    { "target", ("%s (%s)"):format(fmt.target(run), run.kind or "?") },
    { "project", vim.fn.fnamemodify(run.cwd or "", ":~") },
    { "time", fmt.seconds(run.ms) },
    { "tokens", ("in %s · out %s"):format(fmt.tokens(u.tokens_in), fmt.tokens(u.tokens_out)) },
    { "cost", fmt.money(u.cost) },
    { "tier", (run.tier or "main") .. (run.effort and (" · effort " .. run.effort) or "") },
    { "prompt cache", ("read %s · write %s"):format(fmt.tokens(u.cache_read), fmt.tokens(u.cache_write)) },
  }
  if run.error then
    rows[#rows + 1] = { "error", (run.error:gsub("\n", " ")) }
  end
  if run.events and #run.events > 0 then
    local timeline = {}
    for _, e in ipairs(run.events) do
      timeline[#timeline + 1] = ("%s%s @ %s"):format(
        e.event,
        e.detail and e.detail ~= true and (" (" .. tostring(e.detail) .. ")") or "",
        os.date("%H:%M:%S", e.ts)
      )
    end
    rows[#rows + 1] = { "events", table.concat(timeline, " → ") }
  end
  local lines = { ("# %s · %s  %s %s"):format(run.action, fmt.model(run), fmt.icon(run), fmt.outcome(run)), "" }
  local chars = run.chars or {}
  rows[#rows + 1] = {
    "prompt chars",
    ("system %d · message %d (target %d, context %d)"):format(
      chars.system or 0,
      chars.message or 0,
      chars.target or 0,
      chars.context or 0
    ),
  }
  if run.context and #run.context > 0 then
    local parts = {}
    for _, c in ipairs(run.context) do
      parts[#parts + 1] = ("%s %d"):format(c.name, c.chars)
    end
    rows[#rows + 1] = { "context", table.concat(parts, " · ") }
  end
  for _, r in ipairs(rows) do
    lines[#lines + 1] = ("- **%s** %s"):format(r[1], r[2])
  end

  -- an empty instruction is "none" when the run's texts were stored (store_text on), "not stored" otherwise
  if (run.input == nil or run.input == "") and run.prompt then
    vim.list_extend(lines, { "", "## Your instruction", "", "_none_" })
  else
    block(lines, "Your instruction", run.input)
  end

  -- the code that went to the model, in its language
  local target, around = M.code_sent(run.prompt)
  if target or around then
    local lang = run.lang or ""
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Code sent"
    if target then
      lines[#lines + 1] = ""
      lines[#lines + 1] = ("### Target · %s"):format(fmt.target(run))
      lines[#lines + 1] = ""
      code(lines, lang, target)
    end
    if around then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "### Around it (read-only context)"
      lines[#lines + 1] = ""
      code(lines, lang, around)
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Response"
  lines[#lines + 1] = ""
  if run.response and run.response ~= "" then
    answer(lines, run.response)
  else
    lines[#lines + 1] = "_not stored (`settings.agent.history.store_text = false`) or empty_"
  end
  block(lines, "System prompt", run.system)
  block(lines, "Message sent", run.prompt)
  return lines
end

--- EVERYTHING about the run as a single text (to copy or paste wherever needed)
---@param run table
---@return string
function M.text(run)
  return table.concat(M.build(run), "\n") .. "\n"
end

return M
