-- ── Action registry ──────────────────────────────────────────────────────────
-- An action = a fixed recipe: which target it takes, which context it asks for, which prompt
-- it carries and how the result is presented. Contract (fields of each file):
--
--   label      string        short name (status, titles)
--   desc       string        leader menu text
--   key        string        key under <leader>a (under <leader>aA when `advanced`)
--   advanced   boolean?      lives in the Advanced menu (<leader>aA), not in the everyday <leader>a: batch and multi-step work
--   modes      string[]?     mapping modes (default n and x)
--   scope      string        "function" | "class" | "type" | "file" | "lines" | "diagnostic" (a visual selection wins;
--                            "type" = the type under the cursor, or its receiver's if you are in a Go method)
--   context    string[]?     providers from agent/context/providers
--   output     string        presenter: "replace" | "findings" | "text" (agent/output)
--   numbered   boolean?      number the target's lines (per-line findings)
--   input      string?       if it opens the inline instruction field: the field's placeholder
--   input_needed boolean?    with `input_optional`: what is typed is still appended as the winning instruction, but the field cannot be
--              submitted empty (refine)
--   input_optional boolean?  with `input`: Enter on an empty field runs without instruction (implement, docs,
--              fix); without this the text is required (ask, refactor, handoff)
--   enabled    fun(): boolean?  if it returns false the action does not show in the menu (handoff outside Herdr)
--   examples   boolean?      asks the providers for a style example from the project itself (contracts)
--   tier       string?       "light" = runs on the light (cheap) model; default "main"
--   system(env), task(env)   prompts; env = { target, input, language }
--   check(target)            (optional) returns an error if the action does not apply here
--   handler(session)         (optional) replaces the whole model flow (e.g. handoff)
--   standalone  boolean?     the action works on a project or a list, not on the code under the cursor (fix all, fix from
--                            output, plans): no target is resolved, `handler({ selection, action })` takes over
--   verify      boolean?     false = accepting its proposals is not verified afterwards (docs: only comments change)
--
-- Add an action: create `agent/actions/<name>.lua` and add it to NAMES; the menu and
-- the cheatsheet come out on their own.
local M = {}

local NAMES = {
  "implement",
  "review",
  "explain",
  "ask",
  "fix",
  "fix_block",
  "fixall",
  "errors",
  "errors_run",
  "plan",
  "docs",
  "refactor",
  "handoff",
}

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.actions." .. name)
    action.name = name
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
