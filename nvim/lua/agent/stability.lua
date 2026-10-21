-- ── What is stable and what is experimental ──────────────────────────────────
-- The agent has a small core that is held to a standard (tested on every release, measured by `make eval`) and a ring of
-- features that are still finding their shape. Experimental ones keep working but stay out of the menus until you ask
-- for them (`settings.agent.experimental`, or <leader>Sp → Agent), and they say so when they show. Nothing is deleted:
-- a feature moves between the lists below, and that is the whole policy.
--
--   id      what a menu, an action or a feature calls itself by
--   Stable  the everyday core: it fixes, documents, tests, reviews and writes commits, each verifiable for free
--
-- A menu context declares `stability = "<id>"`; an action may declare `stability = "<id>"` too.
local M = {}

--- Experimental features and why (the reason is what the menu and the docs say)
---@type table<string, string>
M.EXPERIMENTAL = {
  ddd = "architecture checks are heuristic: layers and naming are guessed from directory names",
  repository = "port/adapter discovery is only reliable for conventional layouts",
  service = "same limits as repository",
  lenses = "single-focus reviews have no eval cases yet",
  doctor = "troubleshooting quality is not measured yet",
  build = "writing a whole project is the least verifiable thing a model does",
  plan = "multi-file plans depend on the model's planning, which the eval does not cover yet",
}

---@return boolean
local function opted_in()
  if vim.env.NVIM_EXPERIMENTAL == "1" then
    return true -- the generators that document every key (cheatsheet, web docs) must see them all
  end
  local ok, settings = pcall(require, "core.settings")
  return ok and settings.agent.experimental == true
end

---@param id string?
---@return boolean
function M.is_experimental(id)
  return id ~= nil and M.EXPERIMENTAL[id] ~= nil
end

--- Does a feature show up in the menus right now? Stable ones always do
---@param id string?
---@return boolean
function M.visible(id)
  return not M.is_experimental(id) or opted_in()
end

--- Why a feature is experimental ("" for the stable ones)
---@param id string?
---@return string
function M.reason(id)
  return id and M.EXPERIMENTAL[id] or ""
end

--- Group name of a menu: "Agent DDD · experimental"
---@param name string
---@param id string?
---@return string
function M.named(name, id)
  return M.is_experimental(id) and (name .. " · experimental") or name
end

return M
