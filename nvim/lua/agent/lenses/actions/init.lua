-- ── LENS registry (<leader>aL) ────────────────────────────────────────────────
-- A lens is a review with ONE single focus (security, performance...). Each file declares only what
-- sets it apart; the rest is filled in here (target, output as diagnostics, shared prompt). Adding a lens = one
-- file + its name in NAMES; the menu comes out of the registry.
--
--   key      string        key under <leader>aL
--   title    string        short name ("security")
--   focus    string        what it looks for (one long sentence: it is the prompt)
--   gate     string[]?     words: if the code contains NONE of them, the lens does not even call the model (0 tokens)
--   context  string[]?     providers (default, rules and callees: the minimum)
--   tier     string?       "light" = cheap model; default "main"
--   check    fun(target)?  reason not to run (before spending anything)
--
-- Findings are diagnostics with their lens as source (`[security]`): `af`/`aF` fix them, and re-running a lens
-- only replaces its own.
local protocol = require "agent.protocol"
local target_mod = require "agent.context.target"

local M = {}

local NAMES = { "security", "performance", "concurrency", "errors", "api" }

---@type table<string, table>
local cache = {}

---@param spec table
---@return table
local function build(spec)
  local action = {
    label = "lens " .. spec.title,
    desc = spec.title,
    key = spec.key,
    source = spec.title,
    scope = "function",
    context = spec.context or { "rules", "callees" },
    output = "findings",
    numbered = true,
    tier = spec.tier,
    check = function(target)
      if spec.gate then
        local text = table.concat(target.lines, "\n"):lower()
        local hit = false
        for _, word in ipairs(spec.gate) do
          if text:find(word, 1, true) then
            hit = true
            break
          end
        end
        if not hit then
          return ("nothing %s-related in the target: skipped (0 tokens)"):format(spec.title)
        end
      end
      return spec.check and spec.check(target) or nil
    end,
    system = function(env)
      return ("TASK %s review (messages in %s): %s\nReport ONLY %s problems; ignore style and every other kind of bug.\n%s"):format(
        spec.title,
        env.language,
        spec.focus,
        spec.title,
        protocol.FINDINGS_RULES
      )
    end,
    task = function()
      return ("Review <target> only for %s problems."):format(spec.title)
    end,
  }
  return action
end

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = build(require("agent.lenses.actions." .. name))
    action.short = name
    action.name = "lens_" .. name -- `settings.agent.tiers.lens_security = "light"` reassigns it
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

M.target = target_mod -- (for tests)

return M
