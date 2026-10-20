-- ── Desktop app: open a project, on the whole screen ─────────────────────────
-- utils/market.lua with projects: on the left the ones you worked in (newest
-- first), the git projects found under your home (searched in the background,
-- they appear as the search finds them) and ways to start (a folder by path, a
-- new project, a clone); on the right the one under the cursor: where it is, its
-- branch and last commit, when you last opened it, whether a session will bring
-- your windows back, the stack it uses and the start of its README. ⏎ opens it
-- here, o in a new window, d forgets it, / filters. Rows, lines and the pane are
-- pure over the state (tested); `open` wires the keys.
local market = require "utils.market"
local modal = require "utils.modal"
local projects = require "gui.projects"

local M = {}

--- What a folder's files say about its stack (marker file → name), in reading order.
M.MARKERS = {
  { "go.mod", "Go" },
  { "Cargo.toml", "Rust" },
  { "package.json", "JavaScript/TypeScript" },
  { "pyproject.toml", "Python" },
  { "requirements.txt", "Python" },
  { "pubspec.yaml", "Dart/Flutter" },
  { "Package.swift", "Swift" },
  { "pom.xml", "Java" },
  { "build.gradle", "Java/Kotlin" },
  { "build.gradle.kts", "Kotlin" },
  { "Gemfile", "Ruby" },
  { "composer.json", "PHP" },
  { "CMakeLists.txt", "C/C++" },
  { "Makefile", "Make" },
  { "Dockerfile", "Docker" },
  { "docker-compose.yml", "Docker Compose" },
  { "init.lua", "Lua" },
}

---@param dir string
---@return string[]
function M.stack(dir)
  local out, seen = {}, {}
  for _, m in ipairs(M.MARKERS) do
    if not seen[m[2]] and vim.uv.fs_stat(dir .. "/" .. m[1]) then
      seen[m[2]] = true
      out[#out + 1] = m[2]
    end
  end
  return out
end

---@param seconds integer
---@return string "just now", "5 minutes ago", "3 days ago"
function M.ago(seconds)
  local d = os.time() - seconds
  local units = { { 86400 * 30, "month" }, { 86400 * 7, "week" }, { 86400, "day" }, { 3600, "hour" }, { 60, "minute" } }
  for _, u in ipairs(units) do
    if d >= u[1] then
      local n = math.floor(d / u[1])
      return ("%d %s%s ago"):format(n, u[2], n == 1 and "" or "s")
    end
  end
  return "just now"
end

--- The sessions persistence has saved, read once per opening (a file name per project, the folder's path inside).
---@param m table
---@return string[]
local function sessions(m)
  if not m.sessions then
    m.sessions = {}
    local okp, config = pcall(require, "persistence.config")
    local dir = okp and config.options and config.options.dir
    if dir and vim.uv.fs_stat(dir) then
      for name in vim.fs.dir(dir) do
        m.sessions[#m.sessions + 1] = name
      end
    end
  end
  return m.sessions
end

--- The branch and the number of changes from `git status --porcelain --branch`.
---@param out string
---@return string? branch, integer changed
function M.parse_status(out)
  local lines = vim.split(out or "", "\n", { trimempty = true })
  local head = lines[1] and lines[1]:match "^## (.*)$"
  local branch
  if head then
    branch = head:match "^No commits yet on (.+)$"
      or head:match "^Initial commit on (.+)$"
      or head:match "^(.-)%.%.%."
      or head
    branch = branch:match "^HEAD %(no branch%)" and "HEAD (detached)" or branch:gsub("%s.*$", "")
  end
  return branch, #lines - (head and 1 or 0)
end

--- What a project's files say, without git: its stack, the start of its README, whether a session waits for it.
---@param m table
---@param dir string
---@return table
local function local_facts(m, dir)
  local info = { stack = M.stack(dir), git = vim.uv.fs_stat(dir .. "/.git") ~= nil }
  for _, name in ipairs { "README.md", "readme.md", "README", "README.rst" } do
    local f = io.open(dir .. "/" .. name)
    if f then
      info.readme = {}
      for line in f:lines() do
        info.readme[#info.readme + 1] = line
        if #info.readme >= 18 then
          break
        end
      end
      f:close()
      break
    end
  end
  return info
end

--- Reads git for the newest folder asked for, one folder at a time: moving fast over the list starts nothing for
--- the rows only passed over, and the pane is drawn again when the answer is for the row still under the cursor.
---@param m table
local function pump(m)
  local dir = m.want
  if m.busy or not dir or not (m.info[dir] and m.info[dir].pending) then
    return
  end
  m.busy = true
  local results, left = {}, 2
  local function done()
    left = left - 1
    if left > 0 then
      return
    end
    vim.schedule(function()
      m.busy = false
      local info = m.info[dir]
      local st = results.status
      if st and st.code == 0 then
        info.branch, info.changed = M.parse_status(st.stdout)
      end
      local log = results.log
      if log and log.code == 0 then
        local subject, at = vim.trim(log.stdout or ""):match "^(.-)\t(%d+)$"
        info.subject, info.commit_at = subject, tonumber(at)
      end
      info.pending = nil
      -- stamped after git answers: `git status` refreshes .git/index itself
      local cache = require "gui.projcache"
      info.stamp = cache.stamp(dir)
      cache.put(dir, info)
      local row = m.wins and vim.api.nvim_win_is_valid(m.wins.list) and market.current(m)
      if row and row.project and row.project.dir == dir then
        market.refresh(m, true)
      end
      pump(m)
    end)
  end
  local opts = { text = true, timeout = 4000 }
  local ok = pcall(function()
    vim.system({ "git", "-C", dir, "status", "--porcelain", "--branch" }, opts, function(res)
      results.status = res
      done()
    end)
    vim.system({ "git", "-C", dir, "log", "-1", "--format=%s%x09%ct" }, opts, function(res)
      results.log = res
      done()
    end)
  end)
  if not ok then
    m.busy, m.info[dir].pending = false, nil
  end
end

--- Facts about a project for the pane. Saved ones come back at once while the project has not changed (see
--- gui/projcache.lua); otherwise the files are read now and git in the background (the pane says so meanwhile).
---@param m table
---@param dir string
function M.info(m, dir)
  m.info = m.info or {}
  local info = m.info[dir]
  if not info then
    local cache = require "gui.projcache"
    local stamp = cache.stamp(dir)
    info = cache.info(dir, stamp)
    if not info then
      info = local_facts(m, dir)
      info.stamp, info.pending = stamp, info.git or nil
      if not info.git then
        cache.put(dir, info)
      end
    end
    m.info[dir] = info
  end
  -- the session is not saved with the rest: it comes and goes without the project changing (looked up once per opening)
  m.session_of = m.session_of or {}
  if m.session_of[dir] == nil then
    local name = dir:gsub("[\\/:]+", "%%")
    m.session_of[dir] = vim.iter(sessions(m)):any(function(file)
      return file:sub(1, #name) == name and file:sub(-4) == ".vim"
    end)
  end
  info.session = m.session_of[dir]
  if info.pending then
    m.want = dir
    pump(m)
  end
  return info
end

---@param m table
---@param p { dir: string, at: integer? }
local function matches(m, p)
  return m.filter == "" or p.dir:lower():find(m.filter:lower(), 1, true) ~= nil
end

--- The list (pure over m.recent, m.found, m.searching, m.filter)
---@param m table
---@return table[]
function M.rows(m)
  local rows = { { title = "OPEN A PROJECT" }, { spacer = true } }
  local cwd = projects.normalize(vim.uv.cwd() or "")
  local pinned = vim.tbl_filter(function(p)
    return p.pinned and matches(m, p)
  end, m.recent)
  if #pinned > 0 then
    rows[#rows + 1] = { group = "Pinned" }
    for _, p in ipairs(pinned) do
      rows[#rows + 1] = { project = p, current = p.dir == cwd }
    end
    rows[#rows + 1] = { spacer = true }
  end
  local recent = vim.tbl_filter(function(p)
    return not p.pinned and matches(m, p)
  end, m.recent)
  if #recent > 0 then
    rows[#rows + 1] = { group = "Recent" }
    for _, p in ipairs(recent) do
      rows[#rows + 1] = { project = p, current = p.dir == cwd }
    end
    rows[#rows + 1] = { spacer = true }
  end
  local known = {}
  for _, p in ipairs(m.recent) do
    known[p.dir] = true
  end
  local found = vim.tbl_filter(function(p)
    return not known[p.dir] and matches(m, p)
  end, m.found)
  rows[#rows + 1] = { group = "On this machine" }
  for _, p in ipairs(found) do
    rows[#rows + 1] = { project = p, current = p.dir == cwd }
  end
  if m.searching then
    rows[#rows + 1] = { note = "looking for git projects under ~ …" }
  elseif #found == 0 then
    rows[#rows + 1] = { note = m.filter ~= "" and "nothing else matches" or "no other git projects found" }
  end
  rows[#rows + 1] = { spacer = true }
  rows[#rows + 1] = { group = "Start" }
  rows[#rows + 1] = { start = "browse", label = "Browse folders…" }
  rows[#rows + 1] = { start = "path", label = "Open a folder by its path…" }
  rows[#rows + 1] = { start = "new", label = "New project…" }
  rows[#rows + 1] = { start = "clone", label = "Clone a repository…" }
  return rows
end

function M.selectable(row)
  return row.project ~= nil or row.start ~= nil
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
  elseif row.note then
    return { { "    " .. row.note, modal.hl.muted } }
  elseif row.start then
    return { { "  + ", modal.hl.mark }, { row.label, modal.hl.file } }
  end
  local dir = row.project.dir
  local name = vim.fn.fnamemodify(dir, ":t")
  local parent = vim.fn.fnamemodify(vim.fs.dirname(dir), ":~")
  local pad = string.rep(" ", math.max(24 - vim.fn.strdisplaywidth(name), 1))
  return {
    { row.current and "  ● " or (row.project.pinned and "  ★ " or "    "), modal.hl.mark },
    { name, modal.hl.file },
    { pad .. parent, modal.hl.muted },
  }
end

local function line(label, value, hl)
  return { { ("  %-10s"):format(label), "GuiPickerLabel" }, { value, hl or "GuiPickerText" } }
end

---@param m table
---@param row table
---@param width integer
---@return MarketLine[]
function M.pane(m, row, width)
  if not row then
    return {}
  end
  if row.start then
    local text = ({
      browse = "Walk through your folders like in Yazi: h up, l in, the folder under the cursor on the right. ⏎ opens it.",
      path = "Type the folder (~ and relative paths work). Leader opens it here and remembers it.",
      new = "A new folder with git initialized, then opened here. You pick where it goes and its name.",
      clone = "git clone a repository (https or ssh) into a folder you pick, then open it here.",
    })[row.start]
    local out = { { { "  " .. row.label, "GuiPickerTitle" } }, { { "" } } }
    for _, l in ipairs(market.wrap(text, width - 4)) do
      out[#out + 1] = { { "  " .. l, "GuiPickerText" } }
    end
    return out
  end
  if not row.project then
    -- titles, groups and notes (the pane is drawn for whatever row the cursor is on)
    return {}
  end
  local dir = row.project.dir
  local info = M.info(m, dir)
  local out = {
    {
      { "  " .. vim.fn.fnamemodify(dir, ":t"), "GuiPickerTitle" },
      { row.current and "   ● you are here" or "", "GuiPickerMark" },
    },
    { { "  " .. vim.fn.fnamemodify(dir, ":~"), "GuiPickerDim" } },
    { { "" } },
  }
  if info.pending then
    out[#out + 1] = line("Branch", "reading git …", "GuiPickerDim")
  elseif info.branch then
    local changes = info.changed and info.changed > 0 and ("  ·  %d changed"):format(info.changed) or "  ·  clean"
    out[#out + 1] = line("Branch", info.branch .. changes)
  end
  if info.subject and info.subject ~= "" then
    out[#out + 1] = line("Commit", info.subject .. (info.commit_at and ("  ·  " .. M.ago(info.commit_at)) or ""))
  end
  if row.project.at then
    out[#out + 1] = line("Opened", M.ago(row.project.at))
  end
  out[#out + 1] =
    line("Pinned", row.project.pinned and "yes · p unpins it" or "no · p keeps it at the top", "GuiPickerDim")
  if info.session ~= nil then
    out[#out + 1] =
      line("Session", info.session and "brings your windows and files back" or "none yet: starts on the home screen")
  end
  if #info.stack > 0 then
    out[#out + 1] = line("Stack", table.concat(info.stack, " · "), "GuiPickerMark")
  end
  if info.readme then
    out[#out + 1] = { { "" } }
    out[#out + 1] = { { "  README", "GuiPickerLabel" } }
    for _, l in ipairs(info.readme) do
      out[#out + 1] = { { "  " .. l, "GuiPickerDim" } }
    end
  end
  return out
end

function M.summary(m)
  local n = #m.recent + #m.found
  return {
    {
      {
        ("  %d project%s · %s"):format(
          n,
          n == 1 and "" or "s",
          m.searching and "still looking…" or ("searched " .. M.ago(os.time() - (m.found_age or 0)) .. " · R again")
        ),
        modal.hl.muted,
      },
    },
  }
end

function M.hints(_, mode)
  if mode == "pane" then
    return { { "h ← Esc", "back" }, { "⏎", "open" } }
  end
  return {
    { "↑↓ jk", "move" },
    { "l →", "details" },
    { "⏎", "open here" },
    { "o", "new window" },
    { "p", "pin" },
    { "b", "browse" },
    { "d", "forget" },
    { "/", "filter" },
    { "?", "keys" },
  }
end

--- The folders the last search found (still there), at once; the home folder is searched again in the background
--- only when that list is older than `settings.gui.projects.rescan` (or `force`, R).
---@param m table
---@param force boolean?
local function search(m, force)
  local cache = require "gui.projcache"
  local dirs, age = cache.found()
  m.found, m.found_age = {}, age
  for _, dir in ipairs(dirs) do
    if vim.uv.fs_stat(dir) then
      m.found[#m.found + 1] = { dir = dir }
    end
  end
  local rescan = ((require("core.settings").gui or {}).projects or {}).rescan or 3600
  if not force and #dirs > 0 and age < rescan then
    return
  end
  local home = vim.uv.os_homedir() or "~"
  local skip = { ".cache", ".local", ".cargo", ".rustup", ".npm", "node_modules", "go", "snap", ".git/modules" }
  local fd = vim.fn.executable "fd" == 1 and "fd" or (vim.fn.executable "fdfind" == 1 and "fdfind" or nil)
  local cmd
  if fd then
    cmd = { fd, "--hidden", "--no-ignore-vcs", "--type", "d", "--max-depth", "5", "--prune" }
    for _, s in ipairs(skip) do
      vim.list_extend(cmd, { "--exclude", s })
    end
    vim.list_extend(cmd, { "^\\.git$", home })
  else
    cmd = { "find", home, "-maxdepth", "5", "-name", ".git", "-prune", "-not", "-path", "*/.cache/*" }
  end
  m.searching = true
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      local seen, found = {}, {}
      for _, l in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
        -- fd ends folders with a slash: drop it, or the parent of ".git/" would be ".git" itself
        local dir = projects.normalize(vim.fs.dirname((l:gsub("/+$", ""))))
        -- hidden folders (~/.password-store, notes, dotfiles managers) are not projects you open
        local hidden = dir:sub(#home + 1):find "/%." ~= nil
        if not seen[dir] and not hidden then
          seen[dir] = true
          found[#found + 1] = dir
        end
      end
      table.sort(found)
      cache.set_found(found)
      cache.save()
      m.found = vim.tbl_map(function(dir)
        return { dir = dir }
      end, found)
      m.searching, m.found_age = false, 0
      if m.wins and vim.api.nvim_win_is_valid(m.wins.list) then
        market.refresh(m)
      end
    end)
  end)
end

--- Pins or unpins a project and keeps the cursor on it (it moves between Pinned and Recent).
---@param m table
---@param dir string
function M.toggle_pin(m, dir)
  projects.pin(dir, not projects.pinned(dir))
  m.recent = projects.list()
  market.refresh(m)
  for i, r in ipairs(m.rows) do
    if r.project and r.project.dir == dir then
      pcall(vim.api.nvim_win_set_cursor, m.wins.list, { i, 0 })
      break
    end
  end
  market.refresh(m, true)
end

--- Closes the market and opens `dir` as the project, here or in a new window (the picker's and the browser's way).
---@param m table
---@param dir string
---@param new_window boolean?
function M.enter_dir(m, dir, new_window)
  market.close(m)
  if new_window then
    projects.remember(dir)
    if vim.g.leader_gui_channel then
      vim.rpcnotify(vim.g.leader_gui_channel, "leader_window", "new_window:" .. dir)
    end
  else
    projects.switch(dir)
  end
end

---@param m table
---@param row table?
local function open_row(m, row, new_window)
  if not row then
    return
  end
  if row.start then
    market.close(m)
    return M.start(row.start)
  end
  M.enter_dir(m, row.project.dir, new_window)
end

--- The three ways to start without a project in the list.
---@param kind "path"|"new"|"clone"
function M.start(kind)
  if kind == "path" then
    return projects.ask()
  elseif kind == "browse" then
    return require("gui.browse").open()
  end
  local base = vim.fn.fnamemodify(vim.fs.dirname(vim.uv.cwd() or "~"), ":~") .. "/"
  if kind == "new" then
    return modal.input(
      { "Where and with which name" },
      { title = "New project", default = base, confirm = "Create" },
      function(text)
        local dir = projects.normalize(text or "")
        if text == nil or text == "" then
          return
        end
        if vim.uv.fs_stat(dir) then
          return vim.notify("Leader: " .. dir .. " already exists", vim.log.levels.WARN)
        end
        vim.fn.mkdir(dir, "p")
        vim.system({ "git", "init", "-q", dir }):wait(3000)
        projects.switch(dir)
      end
    )
  end
  modal.input({ "Repository to clone (https or ssh)" }, { title = "Clone", confirm = "Next" }, function(url)
    if not url or vim.trim(url) == "" then
      return
    end
    url = vim.trim(url)
    local name = url:gsub("%.git$", ""):match "([^/:]+)$" or "repository"
    modal.input({ "Clone into" }, { title = "Clone", default = base .. name, confirm = "Clone" }, function(text)
      if not text or text == "" then
        return
      end
      local dir = projects.normalize(text)
      vim.notify("Leader: cloning " .. url .. " …", vim.log.levels.INFO)
      vim.system({ "git", "clone", url, dir }, { text = true }, function(res)
        vim.schedule(function()
          if res.code ~= 0 then
            return vim.notify("Leader: clone failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
          end
          projects.switch(dir)
        end)
      end)
    end)
  end)
end

function M.open()
  local def = {
    title = "Open a project",
    rows = M.rows,
    selectable = M.selectable,
    list_line = M.list_line,
    pane = M.pane,
    summary = M.summary,
    hints = M.hints,
    summary_rows = 3,
    hjkl = true, -- l / → read the details, only ⏎ (or a click) opens the project
    read = function(m, row)
      open_row(m, row, false)
    end,
    help = {
      { "o", "open it in a new window" },
      { "p", "pin it: it stays at the top, here and in the projects menu (again to unpin)" },
      { "d", "forget it (the folder stays, it leaves the list)" },
      { "b", "browse your folders to open one (like Yazi)" },
      { "R", "search your home for git projects again (otherwise once an hour)" },
    },
    keys = {
      list = {
        {
          "o",
          function(m, row)
            if row and row.project then
              open_row(m, row, true)
            end
          end,
          "Open in a new window",
        },
        {
          "d",
          function(m, row)
            if row and row.project then
              projects.forget(row.project.dir)
              m.recent = projects.list()
              market.refresh(m)
            end
          end,
          "Forget project",
        },
        {
          "p",
          function(m, row)
            if row and row.project then
              M.toggle_pin(m, row.project.dir)
            end
          end,
          "Pin project",
        },
        {
          "b",
          function(m)
            market.close(m)
            M.start "browse"
          end,
          "Browse folders",
        },
        {
          "R",
          function(m)
            if not m.searching then
              search(m, true)
              market.refresh(m)
            end
          end,
          "Search projects again",
        },
      },
    },
    on_close = function()
      require("gui.projcache").save()
    end,
  }
  local m = market.new(def, { recent = projects.list(), found = {}, info = {} })
  if not m then
    return
  end
  search(m)
  -- the saved list is in place before any search answers (a fresh cache never searches): draw it now
  market.refresh(m)
  return m
end

return M
