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

--- Facts about a project for the pane, read once and kept (git through `git -C`, a short timeout).
---@param m table
---@param dir string
function M.info(m, dir)
  m.info = m.info or {}
  if m.info[dir] then
    return m.info[dir]
  end
  local function git(args)
    local ok, res = pcall(function()
      return vim.system(vim.list_extend({ "git", "-C", dir }, args), { text = true }):wait(600)
    end)
    return ok and res and res.code == 0 and vim.trim(res.stdout or "") or nil
  end
  local info = { stack = M.stack(dir) }
  if vim.uv.fs_stat(dir .. "/.git") then
    info.branch = git { "rev-parse", "--abbrev-ref", "HEAD" }
    info.commit = git { "log", "-1", "--format=%s\t%cr" }
    local status = git { "status", "--porcelain" }
    info.changed = status and #vim.split(status, "\n", { trimempty = true }) or 0
  end
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
  local okp, config = pcall(require, "persistence.config")
  if okp and config.options and config.options.dir then
    local name = dir:gsub("[\\/:]+", "%%")
    info.session = #vim.fn.glob(config.options.dir .. vim.fn.escape(name, "%") .. "*.vim", true, true) > 0
  end
  m.info[dir] = info
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
  local recent = vim.tbl_filter(function(p)
    return matches(m, p)
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
    { row.current and "  ● " or "    ", modal.hl.mark },
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
  if info.branch then
    local changes = info.changed and info.changed > 0 and ("  ·  %d changed"):format(info.changed) or "  ·  clean"
    out[#out + 1] = line("Branch", info.branch .. changes)
  end
  if info.commit and info.commit ~= "" then
    local subject, when = info.commit:match "^(.-)\t(.*)$"
    out[#out + 1] = line("Commit", (subject or info.commit) .. (when and ("  ·  " .. when) or ""))
  end
  if row.project.at then
    out[#out + 1] = line("Opened", M.ago(row.project.at))
  end
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
        ("  %d project%s · %s"):format(n, n == 1 and "" or "s", m.searching and "still looking…" or "search done"),
        modal.hl.muted,
      },
    },
  }
end

function M.hints(_, mode)
  if mode == "pane" then
    return { { "Esc", "back" }, { "⏎", "open" } }
  end
  return { { "⏎", "open here" }, { "o", "new window" }, { "d", "forget" }, { "/", "filter" }, { "?", "keys" } }
end

--- Starts the background search for git projects under the home folder (fd, else find).
---@param m table
local function search(m)
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
      local seen = {}
      for _, l in ipairs(vim.split(res.stdout or "", "\n", { trimempty = true })) do
        -- fd ends folders with a slash: drop it, or the parent of ".git/" would be ".git" itself
        local dir = projects.normalize(vim.fs.dirname((l:gsub("/+$", ""))))
        -- hidden folders (~/.password-store, notes, dotfiles managers) are not projects you open
        local hidden = dir:sub(#home + 1):find "/%." ~= nil
        if not seen[dir] and not hidden then
          seen[dir] = true
          m.found[#m.found + 1] = { dir = dir }
        end
      end
      table.sort(m.found, function(a, b)
        return a.dir < b.dir
      end)
      m.searching = false
      if m.wins and vim.api.nvim_win_is_valid(m.wins.list) then
        market.refresh(m)
      end
    end)
  end)
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
  market.close(m)
  if new_window then
    projects.remember(row.project.dir)
    if vim.g.leader_gui_channel then
      vim.rpcnotify(vim.g.leader_gui_channel, "leader_window", "new_window:" .. row.project.dir)
    end
  else
    projects.switch(row.project.dir)
  end
end

--- The three ways to start without a project in the list.
---@param kind "path"|"new"|"clone"
function M.start(kind)
  if kind == "path" then
    return projects.ask()
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
    read = function(m, row)
      open_row(m, row, false)
    end,
    help = {
      { "o", "open it in a new window" },
      { "d", "forget it (the folder stays, it leaves the list)" },
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
      },
    },
  }
  local m = market.new(def, { recent = projects.list(), found = {}, info = {} })
  search(m)
  return m
end

return M
