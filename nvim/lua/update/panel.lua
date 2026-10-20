-- ── What's new: the changelog and the update, on one full-screen page ────────
-- utils/market.lua: the versions on the left (the ones newer than yours marked ★ and listed first), what each one
-- changed on the right. The changelog is the one fetched with the newer version, or the clone's own CHANGELOG.md
-- when you are up to date. `u` updates (it asks first), `r` looks again, `s` skips the version on offer (the badge
-- goes away until a newer one), `o` opens the release on GitHub. Rows, lines and the pane are pure over the state.
local changelog = require "update.changelog"
local market = require "utils.market"
local modal = require "utils.modal"
local semver = require "update.semver"
local update = require "update"

local M = {}

M.MAX = 12 -- versions listed

---@param seconds integer
---@return string "just now", "3 hours ago"
function M.ago(seconds)
  for _, u in ipairs { { 86400, "day" }, { 3600, "hour" }, { 60, "minute" } } do
    if seconds >= u[1] then
      local n = math.floor(seconds / u[1])
      return ("%d %s%s ago"):format(n, u[2], n == 1 and "" or "s")
    end
  end
  return "just now"
end

---@return ChangelogSection[]
local function sections()
  local saved = require("update.store").get()
  local text = saved.changelog
  if not text then
    local f = io.open((require("update.targets.config").root() or "") .. "/CHANGELOG.md")
    if f then
      text = f:read "*a"
      f:close()
    end
  end
  local all = changelog.sections(text or "")
  while #all > M.MAX do
    table.remove(all)
  end
  return all
end

---@param m table
---@return table[]
function M.rows(m)
  local status = m.status
  local current = status.targets[1] and status.targets[1].current or "0.0.0"
  local rows = { { title = "WHAT'S NEW" }, { spacer = true } }
  local fresh = {}
  for _, s in ipairs(m.sections) do
    local row = { section = s, new = semver.newer(s.version, current), current = s.version == current }
    if row.new then
      fresh[#fresh + 1] = row
    end
  end
  if #fresh > 0 then
    rows[#rows + 1] = { group = "Available" }
    vim.list_extend(rows, fresh)
    rows[#rows + 1] = { spacer = true }
  end
  rows[#rows + 1] = { group = "Installed and before" }
  for _, s in ipairs(m.sections) do
    if not semver.newer(s.version, current) then
      rows[#rows + 1] = { section = s, new = false, current = s.version == current }
    end
  end
  return rows
end

function M.selectable(row)
  return row.section ~= nil
end

---@param row table
---@return MarketLine
function M.list_line(row)
  if row.title then
    return { { "  " .. row.title, modal.hl.key } }
  elseif row.spacer then
    return { { "" } }
  elseif row.group then
    return { { (row.collapsed and "▸ " or "  ") .. row.group:upper(), modal.hl.muted } }
  end
  local s = row.section
  return {
    { row.new and "  ★ " or (row.current and "  ● " or "    "), modal.hl.mark },
    { s.version, modal.hl.file },
    { "   " .. (s.date or ""), modal.hl.muted },
    { row.current and "   installed" or "", modal.hl.muted },
  }
end

function M.pane(_, row, width)
  if not (row and row.section) then
    return {}
  end
  return changelog.render(row.section, width)
end

---@param m table
function M.summary(m)
  local s = m.status
  local lines = {}
  for _, t in ipairs(s.targets) do
    if t.current then
      local text = ("  %s  %s"):format(t.label, t.current)
      if t.available then
        text = text .. "  →  " .. t.latest .. "   update available"
      elseif t.latest then
        text = text .. "   up to date"
      end
      lines[#lines + 1] = { { text, t.available and "GuiWizardOn" or modal.hl.muted } }
    end
  end
  local checked = s.checked_at and ("checked " .. M.ago(os.time() - s.checked_at)) or "never checked"
  if s.error then
    checked = "could not check (" .. s.error:sub(1, 50) .. ") · " .. checked
  end
  if s.skipped then
    checked = checked .. " · version skipped"
  end
  lines[#lines + 1] = { { "  " .. checked, modal.hl.muted } }
  return lines
end

function M.hints(m, mode)
  if mode == "pane" then
    return { { "h ← Esc", "back" } }
  end
  local out = { { "↑↓ jk", "move" }, { "l →", "read" } }
  if m.status.available then
    out[#out + 1] = { "u", "update" }
    out[#out + 1] = { "s", "skip" }
  end
  out[#out + 1] = { "r", "check now" }
  out[#out + 1] = { "o", "on GitHub" }
  out[#out + 1] = { "?", "keys" }
  return out
end

---@param m table
local function reload(m)
  m.status = update.status()
  m.sections = sections()
  market.refresh(m)
end

function M.open()
  local def = {
    title = "What's new",
    rows = M.rows,
    selectable = M.selectable,
    list_line = M.list_line,
    pane = M.pane,
    summary = M.summary,
    hints = M.hints,
    summary_rows = 5,
    hjkl = true,
    initial = function(m)
      for i, r in ipairs(m.rows) do
        if r.section then
          return i
        end
      end
    end,
    help = {
      { "u", "update to the newest version (asks first, never merges or discards)" },
      { "r", "look for a newer version now" },
      { "s", "skip the version on offer: the badge goes away until a newer one" },
      { "o", "open the release page on GitHub" },
    },
    keys = {
      list = {
        {
          "u",
          function(m)
            if not m.status.available then
              return vim.notify("Leader: you are up to date", vim.log.levels.INFO)
            end
            market.close(m)
            update.apply()
          end,
          "Update now",
        },
        {
          "r",
          function(m)
            vim.notify("Leader: looking for updates…", vim.log.levels.INFO)
            update.check {
              force = true,
              done = function()
                if m.wins and vim.api.nvim_win_is_valid(m.wins.list) then
                  reload(m)
                end
              end,
            }
          end,
          "Check now",
        },
        {
          "s",
          function(m)
            update.skip()
            reload(m)
          end,
          "Skip this version",
        },
        {
          "o",
          function(m, row)
            local v = row and row.section and row.section.version or m.status.latest
            local repo = (require("core.settings").update or {}).repo or "sazardev/leader"
            vim.ui.open(("https://github.com/%s/releases/tag/v%s"):format(repo, v or ""))
          end,
          "Open on GitHub",
        },
      },
    },
  }
  return market.new(def, { status = update.status(), sections = sections(), info = {} })
end

return M
