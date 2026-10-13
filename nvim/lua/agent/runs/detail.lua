-- ── A run, complete and readable (markdown) ──────────────────────────────────
-- It is what the history previewer shows: what was asked, with what context, what was
-- sent to the model, what it returned and how much it cost.
local fmt = require "agent.runs.format"

local M = {}

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
  -- a fence longer than any inside the text keeps the content from closing it
  local fence = "```"
  while body:find(fence, 1, true) do
    fence = fence .. "`"
  end
  lines[#lines + 1] = fence .. "text"
  vim.list_extend(lines, vim.split(body, "\n", { plain = true }))
  lines[#lines + 1] = fence
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
  -- in a text block: it reads the same raw (previewer) as rendered (panel)
  local lines =
    { ("# %s · %s  %s %s"):format(run.action, fmt.model(run), fmt.icon(run), fmt.outcome(run)), "", "```text" }
  for _, r in ipairs(rows) do
    lines[#lines + 1] = ("%-13s %s"):format(r[1], r[2])
  end
  local chars = run.chars or {}
  lines[#lines + 1] = ("%-13s system %d · message %d (target %d, context %d)"):format(
    "prompt chars",
    chars.system or 0,
    chars.message or 0,
    chars.target or 0,
    chars.context or 0
  )
  if run.context and #run.context > 0 then
    local parts = {}
    for _, c in ipairs(run.context) do
      parts[#parts + 1] = ("%s %d"):format(c.name, c.chars)
    end
    lines[#lines + 1] = ("%-13s %s"):format("context", table.concat(parts, " · "))
  end
  lines[#lines + 1] = "```"

  block(lines, "Your instruction", run.input)
  block(lines, "Response", run.response)
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
