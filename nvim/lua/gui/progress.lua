-- ── Desktop app: what an install is doing, in numbers ────────────────────────
-- "installing" alone looks hung. A tracker follows a batch of Mason packages (the language tools) and knows, for each
-- one: waiting / running / done / failed, how long it has been going, how many bytes it has downloaded and how fast, and
-- whether data stopped arriving. From that: how many are done of how many, the time spent, a rough time left, a bar.
-- The pure part (formatting, `poll`, `summary`, `lines`) is tested with an injected environment; `begin_mason` wires
-- it to Mason's registry and the staging folders, and is what the app bar and the setup's Install page read
-- (`M.current`).
local M = {}

M.STALL = 20 -- seconds without a byte before it says so

-- ── formatting (pure) ───────────────────────────────────────────────────────

---@param n number bytes
---@return string "812 B", "12.7 MB"
function M.bytes(n)
  if n < 1024 then
    return ("%d B"):format(n)
  elseif n < 1024 * 1024 then
    return ("%.0f KB"):format(n / 1024)
  elseif n < 1024 * 1024 * 1024 then
    return ("%.1f MB"):format(n / 1024 / 1024)
  end
  return ("%.2f GB"):format(n / 1024 / 1024 / 1024)
end

---@param bps number bytes per second
---@return string "31 KB/s"
function M.rate(bps)
  return M.bytes(bps) .. "/s"
end

---@param seconds number
---@return string "45s", "6m 40s", "1h 05m"
function M.dur(seconds)
  seconds = math.max(math.floor(seconds), 0)
  if seconds < 60 then
    return seconds .. "s"
  elseif seconds < 3600 then
    return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
  end
  return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

--- A rough "about 3 min left": minutes, rounded up, never a false precision.
---@param seconds number
---@return string
function M.about(seconds)
  if seconds < 45 then
    return "less than a minute"
  end
  local minutes = math.ceil(seconds / 60)
  return minutes == 1 and "about a minute" or ("about %d min"):format(minutes)
end

---@param fraction number 0..1
---@param width integer
---@return string
function M.bar(fraction, width)
  fraction = math.min(math.max(fraction, 0), 1)
  local full = math.floor(fraction * width + 0.5)
  return string.rep("█", full) .. string.rep("░", width - full)
end

-- ── the tracker (pure over an injected environment) ─────────────────────────

---@class ProgressEnv
---@field installed fun(name: string): boolean
---@field installing fun(name: string): boolean
---@field bytes fun(name: string): integer bytes downloaded so far for that package

---@class ProgressItem
---@field name string
---@field state "waiting"|"running"|"done"|"failed"
---@field started number? when it was first seen running
---@field ended number?
---@field bytes integer
---@field rate number bytes/s, smoothed
---@field last_at number
---@field stalled number? since when no byte arrived

---@param names string[]
---@param env ProgressEnv
---@param now number seconds
---@return table tracker
function M.new(names, env, now)
  local t = { env = env, started = now, items = {}, active = true }
  for _, name in ipairs(names) do
    t.items[#t.items + 1] = { name = name, state = "waiting", bytes = 0, rate = 0, last_at = now }
  end
  return t
end

--- Reads the environment: who is running, who finished, how many bytes, how fast.
---@param t table
---@param now number seconds
function M.poll(t, now)
  for _, it in ipairs(t.items) do
    if it.state == "done" or it.state == "failed" then
      goto continue
    end
    if t.env.installed(it.name) then
      it.state, it.ended = "done", now
    elseif t.env.installing(it.name) then
      if it.state ~= "running" then
        it.state, it.started, it.last_at = "running", now, now
      end
      local bytes = t.env.bytes(it.name)
      local dt = now - it.last_at
      if bytes > it.bytes then
        local instant = dt > 0 and (bytes - it.bytes) / dt or 0
        it.rate = it.rate == 0 and instant or (it.rate * 0.5 + instant * 0.5)
        it.stalled = nil
      else
        it.rate = (dt >= 3) and 0 or it.rate
        it.stalled = it.stalled or it.last_at
      end
      it.bytes, it.last_at = math.max(bytes, it.bytes), now
    elseif it.state == "running" then
      -- it was installing and is not any more without being installed: Mason gave up on it
      it.state, it.ended = "failed", now
    end
    ::continue::
  end
end

--- Mason said it was over: what is not installed did not make it.
---@param t table
---@param now number
function M.finish(t, now)
  M.poll(t, now)
  for _, it in ipairs(t.items) do
    if it.state ~= "done" then
      it.state, it.ended = "failed", it.ended or now
    end
  end
  t.active, t.ended = false, now
end

---@param t table
---@param now number
---@return { total: integer, done: integer, failed: integer, running: integer, waiting: integer, fraction: number, elapsed: number, left: number? }
function M.summary(t, now)
  local s = { total = #t.items, done = 0, failed = 0, running = 0, waiting = 0 }
  for _, it in ipairs(t.items) do
    s[({ done = "done", failed = "failed", running = "running", waiting = "waiting" })[it.state]] = s[it.state] + 1
  end
  s.fraction = s.total > 0 and (s.done + s.failed) / s.total or 1
  s.elapsed = (t.ended or now) - t.started
  -- a rough pace only once a few have finished (the last one is often the big download)
  local finished = s.done + s.failed
  if t.active and finished >= 3 and finished < s.total then
    s.left = s.elapsed / finished * (s.total - finished)
  end
  return s
end

--- One running item as a sentence: "downloading 12.7 MB · 31 KB/s · 6m 40s" or the warning when data stopped.
---@param it ProgressItem
---@param now number
---@return string text, boolean stalled
function M.describe(it, now)
  if it.state == "waiting" then
    return "waiting for a free slot", false
  elseif it.state == "done" then
    return "done in " .. M.dur((it.ended or now) - (it.started or it.ended or now)), false
  elseif it.state == "failed" then
    return "did not install", false
  end
  local spent = M.dur(now - (it.started or now))
  if it.bytes == 0 then
    return "starting · " .. spent, false
  end
  if it.stalled and now - it.stalled >= M.STALL then
    return ("no data for %s · slow or blocked connection? · %s"):format(M.dur(now - it.stalled), spent), true
  end
  local parts = { "downloading " .. M.bytes(it.bytes) }
  if it.rate > 0 then
    parts[#parts + 1] = M.rate(it.rate)
  end
  parts[#parts + 1] = spent
  return table.concat(parts, " · "), false
end

--- The bar's one line: "7/9 · codelldb 12.7 MB 31 KB/s · 6m 40s".
---@param t table
---@param now number
---@return string, number percent
function M.status_text(t, now)
  local s = M.summary(t, now)
  local parts = { ("%d/%d"):format(s.done + s.failed, s.total) }
  for _, it in ipairs(t.items) do
    if it.state == "running" then
      local line = it.name
      if it.bytes > 0 then
        line = line .. " " .. M.bytes(it.bytes) .. (it.rate > 0 and (" " .. M.rate(it.rate)) or "")
      end
      parts[#parts + 1] = line
      break
    end
  end
  parts[#parts + 1] = M.dur(s.elapsed)
  return table.concat(parts, " · "), s.fraction * 100
end

--- The page: a header, the bar, one row per package (segments `{ text, hl }`, the wizard's highlight groups).
---@param t table
---@param now number
---@param width integer
---@param spin string a spinner frame
---@return table[][] lines
function M.lines(t, now, width, spin)
  local s = M.summary(t, now)
  local out = {}
  local head = { { ("LANGUAGE TOOLS  ·  %d of %d"):format(s.done + s.failed, s.total), "GuiPickerLabel" } }
  head[#head + 1] = { "  ·  " .. M.dur(s.elapsed), "GuiPickerDim" }
  if s.failed > 0 then
    head[#head + 1] = { ("  ·  %d failed"):format(s.failed), "GuiWizardBad" }
  end
  out[#out + 1] = head
  local barw = math.min(width - 30, 40)
  local tail = ("  %d%%"):format(math.floor(s.fraction * 100))
  if s.left then
    tail = tail .. "  ·  " .. M.about(s.left) .. " left, roughly"
  end
  out[#out + 1] = {
    { M.bar(s.fraction, barw), s.failed > 0 and "GuiWizardKey" or "GuiWizardOn" },
    { tail, "GuiPickerDim" },
  }
  out[#out + 1] = { { "" } }
  local namew = 0
  for _, it in ipairs(t.items) do
    namew = math.max(namew, #it.name)
  end
  local any_stalled
  for _, it in ipairs(t.items) do
    local text, stalled = M.describe(it, now)
    any_stalled = any_stalled or stalled
    local mark, hl = "○", "GuiPickerDim"
    if it.state == "done" then
      mark, hl = "✓", "GuiWizardOn"
    elseif it.state == "failed" then
      mark, hl = "✗", "GuiWizardBad"
    elseif it.state == "running" then
      mark, hl = spin, stalled and "GuiWizardKey" or "GuiWizardOn"
    end
    out[#out + 1] = {
      { "  " .. mark .. "  ", hl },
      {
        it.name .. string.rep(" ", namew - #it.name) .. "   ",
        it.state == "waiting" and "GuiPickerDim" or "GuiPickerText",
      },
      { text, (stalled and "GuiWizardKey") or (it.state == "failed" and "GuiWizardBad") or "GuiPickerDim" },
    }
  end
  if any_stalled then
    out[#out + 1] = { { "" } }
    out[#out + 1] = {
      {
        "  Downloads from GitHub can crawl: it keeps trying by itself. Another big download on this connection",
        "GuiPickerDim",
      },
    }
    out[#out + 1] = { { "  (a docker build, a sync) slows it down; close it and this speeds up.", "GuiPickerDim" } }
  end
  return out
end

-- ── the real environment: Mason ─────────────────────────────────────────────

--- Bytes under a folder, bounded (a package's staging folder: the download, or the venv being built).
---@param path string
---@param budget integer? entries to look at at most
---@return integer
function M.dir_bytes(path, budget)
  budget = budget or 3000
  local total = 0
  local function walk(dir)
    local handle = vim.uv.fs_scandir(dir)
    while handle and budget > 0 do
      local name, kind = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      budget = budget - 1
      local full = dir .. "/" .. name
      if kind == "directory" then
        walk(full)
      else
        local st = vim.uv.fs_stat(full)
        total = total + (st and st.size or 0)
      end
    end
  end
  walk(path)
  return total
end

M.current = nil ---@type table? the tracker of the language tools, while it runs and after it

local timer

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

---@param name string
---@return string
local function package_name(name)
  return (name:gsub("@.*$", ""))
end

--- Starts following the language tools Mason is about to install (idempotent while one is running).
---@param names string[]? the packages (default: the ones the languages want that are not installed)
function M.begin_mason(names)
  if M.current and M.current.active then
    return M.current
  end
  local ok, registry = pcall(require, "mason-registry")
  if not ok then
    return nil
  end
  if not names then
    names = {}
    for _, want in ipairs(require("languages").mason()) do
      local pkg = package_name(want)
      if not registry.is_installed(pkg) then
        names[#names + 1] = pkg
      end
    end
  end
  if #names == 0 then
    return nil
  end
  local staging = vim.fn.stdpath "data" .. "/mason/staging/"
  local installing = {}
  local function refresh_installing()
    installing = {}
    for _, pkg in ipairs(registry.get_all_packages()) do
      if pkg:is_installing() then
        installing[pkg.name] = true
      end
    end
  end
  refresh_installing()
  local t = M.new(names, {
    installed = function(name)
      return registry.is_installed(name)
    end,
    installing = function(name)
      return installing[name] == true
    end,
    bytes = function(name)
      return M.dir_bytes(staging .. name)
    end,
  }, os.time())
  M.current = t
  stop_timer()
  timer = vim.uv.new_timer()
  timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      if not t.active then
        return stop_timer()
      end
      refresh_installing()
      M.poll(t, os.time())
      pcall(function()
        require("gui").update()
      end)
    end)
  )
  return t
end

--- Mason is done with the batch: close it, and say what happened.
function M.end_mason()
  local t = M.current
  if not (t and t.active) then
    return
  end
  stop_timer()
  M.finish(t, os.time())
  local s = M.summary(t, os.time())
  if s.failed > 0 then
    local names = vim.tbl_map(
      function(it)
        return it.name
      end,
      vim.tbl_filter(function(it)
        return it.state == "failed"
      end, t.items)
    )
    vim.notify(
      ("Leader: %d of %d language tools installed in %s. Not installed: %s. Press Install again to retry."):format(
        s.done,
        s.total,
        M.dur(s.elapsed),
        table.concat(names, ", ")
      ),
      vim.log.levels.WARN
    )
  else
    vim.notify(("Leader: %d language tools installed in %s."):format(s.done, M.dur(s.elapsed)), vim.log.levels.INFO)
  end
end

return M
