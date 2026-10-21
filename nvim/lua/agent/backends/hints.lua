-- ── What to do about a backend's error (pure) ────────────────────────────────
-- A CLI's error text says what happened, rarely what to do: "Unexpected server error (err_4c1e…)" tells nobody that the
-- provider rejected the account. Each rule below is a pattern of an error seen in practice and the one line of advice that
-- goes after it. The message is never replaced, only completed; an error nobody knows is returned as it came.
local M = {}

---@type { [1]: string, [2]: string, [3]: string? }[] pattern (lowercase), advice, backend it is for (nil = any)
local RULES = {
  {
    "blocked by a gateway",
    "the provider's gateway refused the request: check the account and plan for this model, or the network (a proxy or VPN)",
    "opencode",
  },
  {
    "unexpected server error",
    "the provider failed on its side or refused the account: try another model (`opencode models`) or run `opencode auth login`",
    "opencode",
  },
  { "forbidden", "the account has no access to this model: pick another with <leader>am", nil },
  { "not logged in", "log in once in a terminal (`claude` / `opencode auth login`) and try again", nil },
  { "invalid api key", "the key is wrong or expired: set it again (see the backend's setup)", nil },
  { "credit balance", "the account is out of credit: top it up or pick another model/backend with <leader>am", nil },
  {
    "rate limit",
    "rate limited: wait a minute, or use another model/backend (the cascade can do it for you: settings.agent.cascade)",
    nil,
  },
  { "overloaded", "the provider is overloaded: try again in a moment, or another model", nil },
  { "context length", "the request is bigger than the model's window: select less code", nil },
  { "timed out", "no answer in time: a smaller target, a faster model, or settings.agent.timeout_ms", nil },
}

--- The error with one line of advice after it, when a rule knows it
---@param backend string?
---@param message string?
---@return string
function M.explain(backend, message)
  message = message or ""
  local low = message:lower()
  for _, rule in ipairs(RULES) do
    if (not rule[3] or rule[3] == backend) and low:find(rule[1], 1, true) then
      if low:find(rule[2]:sub(1, 20):lower(), 1, true) then
        return message -- already says it
      end
      return message .. " — " .. rule[2]
    end
  end
  return message
end

return M
