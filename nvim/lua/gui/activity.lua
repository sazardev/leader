-- ── Desktop app: Activity Center feed ────────────────────────────────────────
-- The app bar only keeps the newest job. This module keeps a short, structured history and writes an atomic JSON
-- snapshot that the optional `leader-activity` OpenTUI binary can tail. Neovim remains the source of truth: the TUI
-- reads the feed and never starts jobs or changes files itself.
local settings = require "core.settings"

local M = {}

---@type { running: table<string, table>, events: table[], seq: integer, timer: uv_timer? }
local state = { running = {}, events = {}, seq = 0 }

--- One snapshot per Neovim process, so two Leader windows never mix their activity.
M.FILE = vim.fn.stdpath "cache" .. "/leader-activity-" .. vim.fn.getpid() .. ".json"

---@return integer epoch milliseconds, readable from another process
local function now_ms()
  return os.time() * 1000 + math.floor((vim.uv.hrtime() % 1_000_000_000) / 1_000_000)
end

local function cfg()
  return settings.gui.activity or {}
end

---@return integer
local function max_events()
  return math.max(20, tonumber(cfg().max_events) or 200)
end

---@param value any
---@return any
local function clean(value)
  if type(value) ~= "string" then
    return nil
  end
  value = vim.trim(value)
  if #value > 500 then
    value = vim.fn.strcharpart(value, 0, 500)
  end
  return value ~= "" and value or nil
end

---@param key string
---@return table?
function M.get(key)
  return state.running[key]
end

--- The newest running job, for the app bar.
---@return table?
function M.newest()
  local newest
  for _, item in pairs(state.running) do
    if not newest or item.updated_at > newest.updated_at then
      newest = item
    end
  end
  return newest
end

---@return table[]
function M.running()
  local list = vim.tbl_values(state.running)
  table.sort(list, function(a, b)
    return a.started_at < b.started_at
  end)
  return list
end

---@return table[]
function M.events()
  return vim.deepcopy(state.events)
end

---@param key string
---@param name string
---@param title string?
---@param message string?
---@param percent number?
---@param target string?
---@return table
function M.begin(key, name, title, message, percent, target)
  local at = now_ms()
  local item = state.running[key]
  if not item then
    state.seq = state.seq + 1
    item = {
      id = key,
      seq = state.seq,
      name = clean(name) or "task",
      state = "running",
      started_at = at,
      updated_at = at,
    }
    state.running[key] = item
    table.insert(state.events, 1, item)
  end
  item.name = clean(name) or item.name
  item.title = clean(title)
  item.message = clean(message)
  item.target = clean(target)
  item.percent = tonumber(percent)
  item.updated_at = at
  M.publish()
  return item
end

--- Updates only the progress fields of a running job; equal values do not rewrite the feed.
---@param key string
---@param message string?
---@param percent number?
function M.progress(key, message, percent)
  local item = state.running[key]
  if not item then
    return
  end
  message, percent = clean(message), tonumber(percent)
  if item.message == message and item.percent == percent then
    return
  end
  item.message, item.percent, item.updated_at = message, percent, now_ms()
  M.publish()
end

--- Finishes a running job, or records a one-off completed event such as a save.
---@param key string
---@param text string?
---@param outcome "done"|"error"|"cancelled"|"denied"?
---@param name string?
function M.done(key, text, outcome, name)
  local at = now_ms()
  local item = state.running[key]
  if not item then
    state.seq = state.seq + 1
    item = {
      id = key,
      seq = state.seq,
      name = clean(name) or key:match "^([^:]+)" or "task",
      state = outcome or "done",
      started_at = at,
      updated_at = at,
    }
    table.insert(state.events, 1, item)
  end
  state.running[key] = nil
  item.state = outcome or "done"
  local detail = clean(text)
  if detail then
    if item.title then
      item.message = detail
    else
      item.title = detail
    end
  end
  item.percent = item.state == "done" and 100 or item.percent
  item.finished_at = at
  item.updated_at = at
  local cap = max_events()
  if #state.events > cap then
    for i = #state.events, cap, -1 do
      state.events[i] = nil
    end
  end
  M.publish()
end

---@return table
function M.snapshot()
  return {
    version = 1,
    pid = vim.fn.getpid(),
    cwd = vim.uv.cwd() or "",
    updated_at = now_ms(),
    running = M.running(),
    events = M.events(),
  }
end

--- Writes the snapshot now. The temporary file lives beside it, so rename is atomic on the same filesystem.
function M.flush()
  if cfg().enabled == false then
    return false
  end
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  vim.fn.mkdir(vim.fs.dirname(M.FILE), "p")
  local tmp = M.FILE .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    return false
  end
  f:write(vim.json.encode(M.snapshot()))
  f:close()
  local ok = vim.uv.fs_rename(tmp, M.FILE)
  if not ok then
    -- Windows does not replace an existing file with rename.
    os.remove(M.FILE)
    ok = vim.uv.fs_rename(tmp, M.FILE)
  end
  return ok
end

--- Coalesces LSP progress bursts into one small write.
function M.publish()
  if cfg().enabled == false or state.timer then
    return
  end
  local timer = assert(vim.uv.new_timer())
  state.timer = timer
  timer:start(60, 0, function()
    timer:close()
    if state.timer == timer then
      state.timer = nil
    end
    vim.schedule(M.flush)
  end)
end

--- Forgets the in-memory history (tests, or an explicit clear later).
function M.reset()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  state = { running = {}, events = {}, seq = 0 }
end

--- Removes this process's feed when Neovim exits.
function M.setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("LeaderActivityFeed", { clear = true }),
    callback = function()
      M.flush()
      os.remove(M.FILE)
    end,
  })
end

--- Finds the optional binary: an explicit setting, PATH, then this checkout's build output.
---@return string?
function M.binary()
  local configured = clean(cfg().binary)
  if configured and vim.fn.executable(configured) == 1 then
    return configured
  end
  local on_path = vim.fn.exepath "leader-activity"
  if on_path ~= "" then
    return on_path
  end
  local source = vim.fn.resolve(debug.getinfo(1, "S").source:sub(2))
  local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))))
  for _, rel in ipairs {
    "app/target/activity/leader-activity",
    "app/tools/leader-activity/target/debug/leader-activity",
    "app/tools/leader-activity/target/release/leader-activity",
    "app/target/debug/leader-activity",
    "app/target/release/leader-activity",
  } do
    local path = root .. "/" .. rel
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  return nil
end

---@return boolean
function M.available()
  return cfg().enabled ~= false and M.binary() ~= nil
end

--- Opens the Activity Center in the same floating terminal used by other TUIs. The process survives hiding it; q exits.
function M.open()
  if cfg().enabled == false then
    vim.notify("Activity Center is disabled in settings.gui.activity", vim.log.levels.WARN)
    return
  end
  local binary = M.binary()
  if not binary then
    vim.notify("Activity Center is not built. Run: make activity", vim.log.levels.WARN)
    return
  end
  M.flush()
  pcall(require("lazy").load, { plugins = { "toggleterm.nvim" } })
  local cmd = ("%s --file %s"):format(vim.fn.shellescape(binary), vim.fn.shellescape(M.FILE))
  require("utils.terminal").float_repl("Leader Activity", cmd, vim.uv.cwd() or vim.fn.getcwd())
  pcall(function()
    require("gui").update()
  end)
end

---@return boolean
function M.is_open()
  local term = require("utils.terminal").named "Leader Activity"
  return term ~= nil and term:is_open()
end

return M
