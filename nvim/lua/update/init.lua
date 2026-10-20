-- ── Updates: is there a newer Leader, what changed, bring it in ──────────────
-- One tiny request now and then (`source.lua`, `settings.update`) says whether GitHub has a newer version. The answer is
-- saved (`store.lua`), announced once per version and drawn as a badge in the app bar (gui/init.lua chips, action
-- `update`) and a line in the logo's menu; the panel (`panel.lua`) shows the changelog and updates on request. What is
-- updated are TARGETS (`targets/<id>.lua`: the config clone, the desktop app): adding one = a file + its id here.
-- Nothing is ever changed without a yes that names what will happen.
--
--   M.status()        what is installed, what is newest, what can be updated (pure over the saved answer)
--   M.check(opts)     looks it up (async); opts.force skips the interval; fires User LeaderUpdateChecked
--   M.apply()         asks, then updates every target that is behind, one after the other
--   M.skip()          hides the badge for the version on offer until a newer one comes
--   M.setup()         the automatic check (a few seconds after start, then every hour it is due)
local semver = require "update.semver"
local store = require "update.store"

local M = {}

M.TARGETS = { "config", "app" }

---@return table settings.update with its defaults
local function cfg()
  return vim.tbl_extend(
    "force",
    { enabled = true, check_hours = 12, notify = true, repo = "sazardev/leader", branch = "master" },
    require("core.settings").update or {}
  )
end

---@return table[] the targets that apply here, loaded
local function targets()
  local out = {}
  for _, id in ipairs(M.TARGETS) do
    out[#out + 1] = require("update.targets." .. id)
  end
  return out
end

---@class UpdateTargetStatus
---@field id string
---@field label string
---@field current string?
---@field latest string?
---@field available boolean

--- What is known, without any I/O but the saved file.
---@param saved table? the store's contents (tests inject theirs)
---@param list table[]? the targets (tests inject theirs)
---@return { targets: UpdateTargetStatus[], available: boolean, latest: string?, skipped: boolean, checked_at: integer?, error: string?, changelog: string? }
function M.status(saved, list)
  saved = saved or store.get()
  local info = { version = saved.latest, release = saved.release }
  local out =
    { targets = {}, available = false, checked_at = saved.checked_at, error = saved.error, changelog = saved.changelog }
  for _, t in ipairs(list or targets()) do
    local current, latest = t.current(), saved.latest and t.latest(info) or nil
    local behind = current ~= nil and semver.newer(latest, current)
    out.targets[#out.targets + 1] =
      { id = t.id, label = t.label, current = current, latest = latest, available = behind }
    if behind then
      out.available = true
      out.latest = out.latest and (semver.newer(latest, out.latest) and latest or out.latest) or latest
    end
  end
  out.skipped = out.available and saved.skipped == out.latest
  return out
end

--- Is there something to offer (a newer version that was not skipped)?
---@return boolean, string? the version on offer
function M.offer()
  local s = M.status()
  return s.available and not s.skipped, s.latest
end

---@return boolean it is time to look again
function M.due()
  local c = cfg()
  if not c.enabled then
    return false
  end
  local saved = store.get()
  local every = (saved.error and 1 or c.check_hours) * 3600 -- a failed look is retried after an hour
  return os.time() - (saved.checked_at or 0) >= every
end

---@type boolean
local checking = false

--- Looks it up. `opts.force` ignores the interval; `opts.done(status)` hears the result.
---@param opts? { force: boolean?, done: fun(status: table)? }
function M.check(opts)
  opts = opts or {}
  if checking or not (opts.force or M.due()) then
    return
  end
  checking = true
  local current = require("update.targets.config").current() or "0.0.0"
  require("update.source").fetch(cfg(), current, function(info, err)
    checking = false
    if not info then
      store.set { checked_at = os.time(), error = err or "failed" }
    else
      local patch =
        { checked_at = os.time(), error = vim.NIL, latest = info.version, release = info.release or vim.NIL }
      if info.changelog then
        patch.changelog = info.changelog
      end
      store.set(patch)
    end
    local status = M.status()
    vim.api.nvim_exec_autocmds("User", { pattern = "LeaderUpdateChecked", modeline = false })
    -- once per version, and not for one that was skipped
    if status.available and not status.skipped and cfg().notify and store.get().announced ~= status.latest then
      store.set { announced = status.latest }
      vim.notify(
        ("Leader %s is available (you have %s). Click the badge or Space S u to see what changed."):format(
          status.latest,
          status.targets[1] and status.targets[1].current or "?"
        ),
        vim.log.levels.INFO
      )
    end
    if opts.done then
      opts.done(status)
    end
  end)
end

function M.skip()
  local _, latest = M.offer()
  if latest then
    store.set { skipped = latest }
    vim.api.nvim_exec_autocmds("User", { pattern = "LeaderUpdateChecked", modeline = false })
  end
end

--- Asks, then updates every target that is behind (the config first). `done()` when over.
---@param done fun()?
function M.apply(done)
  local status = M.status()
  local behind = vim.tbl_filter(function(t)
    return t.available
  end, status.targets)
  if #behind == 0 then
    return vim.notify("Leader: nothing to update", vim.log.levels.INFO)
  end
  local lines = {}
  for _, t in ipairs(behind) do
    lines[#lines + 1] = ("%s  %s → %s"):format(t.label, t.current, t.latest)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "The config is pulled with git (never merged or discarded) and the plugins are restored to the lockfile."
  require("utils.modal").confirm(lines, { title = "Update Leader", confirm = "Update" }, function()
    local loaded = {}
    for _, t in ipairs(targets()) do
      loaded[t.id] = t
    end
    local failed, messages = false, {}
    local function step(i)
      local t = behind[i]
      if not t then
        store.reset()
        vim.api.nvim_exec_autocmds("User", { pattern = "LeaderUpdateChecked", modeline = false })
        vim.notify("Leader: " .. table.concat(messages, "; "), failed and vim.log.levels.WARN or vim.log.levels.INFO)
        if not failed and vim.g.leader_gui_channel then
          require("utils.modal").confirm(
            { "Updated. Restart Leader now to use it?" },
            { title = "Restart", confirm = "Restart now" },
            function()
              vim.rpcnotify(vim.g.leader_gui_channel, "leader_window", "restart:" .. (vim.uv.cwd() or ""))
            end
          )
        end
        return done and done()
      end
      local info = { version = store.get().latest, release = store.get().release }
      loaded[t.id].apply(info, function(ok, message)
        failed = failed or not ok
        messages[#messages + 1] = t.label .. ": " .. message
        if ok then
          step(i + 1)
        else
          step(#behind + 1) -- stop at the first that fails
        end
      end)
    end
    step(1)
  end)
end

function M.setup()
  if not cfg().enabled then
    return
  end
  local group = vim.api.nvim_create_augroup("LeaderUpdate", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      -- out of the way of the first frame and of the guided setup
      vim.defer_fn(M.check, 8000)
      local timer = vim.uv.new_timer()
      timer:start(
        3600 * 1000,
        3600 * 1000,
        vim.schedule_wrap(function()
          M.check()
        end)
      )
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
          timer:stop()
          timer:close()
        end,
      })
    end,
  })
end

return M
