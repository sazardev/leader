-- Guard: is this model's profile (agent/profiles.lua) up to this request? A weak model is not asked what it fails at: a
-- target past its size limit, or an action the eval measured it to fail, is declined BEFORE anything is sent, with what to
-- do instead. (With the cascade on the pipeline sends those to the main model before they ever reach this guard.)
local M = {}

---@param req table
---@return { level: string, title: string, message: string?, lines: table }?
function M.check(req)
  local lim = req.limits
  if not lim then
    return nil
  end
  local who = ("%s/%s"):format(req.backend or "?", req.model or "default")
  local why
  if lim.declined then
    why = ("%s: %s"):format(who, lim.declined)
  elseif lim.max_target_lines and (req.target_lines or 0) > lim.max_target_lines then
    why = ("%s (%s profile) is held to %d lines; this target has %d"):format(
      who,
      req.profile or "small",
      lim.max_target_lines,
      req.target_lines
    )
  end
  if not why then
    return nil
  end
  local advice = "select fewer lines, or pick a stronger model (<leader>am)"
  return { level = "block", title = "Agent capability", message = why .. ": " .. advice, lines = {} }
end

return M
