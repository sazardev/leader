-- ── Settings panel (<leader>S) ───────────────────────────────────────────────
-- One flat list of the things worth changing without opening a file: Enter flips a toggle, steps through a short list of
-- values (or opens a picker for a long one) and runs an action. A choice applies at once when it can, is saved apart
-- (prefs/store.lua, wins over settings.lua and local.lua) and says so when it needs a restart.
--
-- Each group is a file in `prefs/items/` returning a list of items (add one = a line there, a group = a file + `NAMES`):
--
--   group    string        column of the list ("Appearance")
--   label    string        what it changes ("Motion")
--   kind     string        "toggle" | "choice" | "action"
--   id       string?       path in core.settings ("ui.motion"): the value is read from it and, on change, written to it and
--                          saved. Without `id` the item owns its state: it needs `get`, and `apply` persists it itself
--   get      fun(): any?   current value when it does not come from `id` (diagnostic blocks keep their own file)
--   choices  { value, label }[]?  a toggle is on/off; a choice lists its values (a nil `value` removes the saved choice)
--   apply    fun(value)?   live effect (set vim.o.autoread...); not needed when the setting is read where it is used
--   restart  boolean?      it only takes effect on the next start (the note says so)
--   run      fun()?        what an action does
--   show     fun(): string?  value column of an action ("gruvbox"); default "›"
local log = require "utils.log"
local settings = require "core.settings"
local store = require "prefs.store"

local M = {}

local NAMES = { "appearance", "edit", "diagnostics", "agent", "languages", "system" }

---@type table[]?
local cache

--- More values than this and Enter opens a picker instead of stepping through them
local CYCLE_MAX = 3

---@return table[]
function M.items()
  if not cache then
    cache = {}
    for _, name in ipairs(NAMES) do
      vim.list_extend(cache, require("prefs.items." .. name))
    end
  end
  return cache
end

---@param id string
---@return table?
function M.find(id)
  for _, item in ipairs(M.items()) do
    if item.id == id then
      return item
    end
  end
end

---@param item table
---@return { value: any, label: string }[]
function M.choices(item)
  if item.kind == "toggle" then
    return { { value = true, label = "on" }, { value = false, label = "off" } }
  end
  return item.choices or {}
end

---@param item table
---@return any
function M.value(item)
  if item.get then
    return item.get()
  end
  if item.id then
    return store.get(settings, item.id)
  end
end

---@param item table
---@return string
function M.text(item)
  if item.kind == "action" then
    return item.show and item.show() or "›"
  end
  local value = M.value(item)
  for _, c in ipairs(M.choices(item)) do
    if vim.deep_equal(c.value, value) then
      return c.label
    end
  end
  return value == nil and "default" or tostring(value)
end

--- Applies a value: now, saved, and with a word about it
---@param item table
---@param value any
function M.set(item, value)
  if item.id then
    store.set(settings, item.id, value)
    store.save(item.id, value)
  end
  if item.apply then
    local ok, err = pcall(item.apply, value)
    if not ok then
      log.warn(("Settings: %s did not apply (%s)"):format(item.label, tostring(err)))
    end
  end
  log.info(("%s: %s%s"):format(item.label, M.text(item), item.restart and " (applies on restart)" or ""))
end

--- The next value of a toggle or a short list
---@param item table
function M.cycle(item)
  local choices = M.choices(item)
  if #choices == 0 then
    return
  end
  local current = M.value(item)
  local at = 0
  for i, c in ipairs(choices) do
    if vim.deep_equal(c.value, current) then
      at = i
    end
  end
  M.set(item, choices[at % #choices + 1].value)
end

--- The list's rows: `Group  Label  value`, columns aligned
---@param items table[]
---@return string[]
function M.rows(items)
  local gw, lw = 0, 0
  for _, item in ipairs(items) do
    gw, lw = math.max(gw, vim.fn.strdisplaywidth(item.group)), math.max(lw, vim.fn.strdisplaywidth(item.label))
  end
  return vim.tbl_map(function(item)
    local function pad(text, width)
      return text .. (" "):rep(width - vim.fn.strdisplaywidth(text))
    end
    return ("%s  %s  %s"):format(pad(item.group, gw), pad(item.label, lw), M.text(item))
  end, items)
end

---@param index integer?  row to land on (the one just changed)
function M.open(index)
  local items = M.items()
  local rows = M.rows(items)
  local list = {}
  for i, item in ipairs(items) do
    list[i] = { label = rows[i], item = item, at = i }
  end
  require("agent.ui.select").pick(list, { title = "Settings", index = index }, function(row)
    M.activate(row.item, row.at)
  end)
end

--- Forgets every saved choice (the next start reads settings.lua and local.lua again)
function M.reset()
  require("utils.modal").confirm({
    "Forget every choice made in the settings panel?",
    { { "They go back to settings.lua and local.lua on the next start.", "NvModalMuted" } },
  }, { title = "Reset settings", confirm = "Reset", danger = true }, function()
    store.clear()
    log.info "Settings: saved choices forgotten (restart to apply)"
  end)
end

--- Enter on a row
---@param item table
---@param at integer
function M.activate(item, at)
  local function again()
    vim.schedule(function()
      M.open(at)
    end)
  end
  if item.kind == "action" then
    return item.run()
  end
  local choices = M.choices(item)
  if #choices <= CYCLE_MAX then
    M.cycle(item)
    return again()
  end
  local current = M.value(item)
  local list = vim.tbl_map(function(c)
    return { label = c.label, value = c.value, current = vim.deep_equal(c.value, current) }
  end, choices)
  require("agent.ui.select").pick(list, { title = item.label, on_cancel = again }, function(choice)
    M.set(item, choice.value)
    again()
  end)
end

return M
