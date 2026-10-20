-- ── Desktop app: browse folders to open one (the picker's "Browse folders…", key b) ──
-- Yazi-like: the folders of the one you are in on the left, and what the one under the cursor holds on the right
-- (its subfolders and files, and for a git project its branch, last commit and stack). h / ← goes up, l / → goes in,
-- ⏎ opens the folder under the cursor as the project, `.` shows hidden folders, ~ goes home, / filters, o opens it in
-- a new window, p pins it. Starts in the folder above the current project with the project selected. Listings are read
-- once per visit (a fast sweep never touches the disk twice); the pure parts (`rows`, `list_line`) are tested.
local market = require "utils.market"
local modal = require "utils.modal"
local picker = require "gui.picker"
local projects = require "gui.projects"

local M = {}

M.PREVIEW = 60 -- entries listed in the pane

--- The folders and files of `dir`, sorted (folders first, names case-insensitive); nil when it cannot be read.
---@param dir string
---@return { dirs: string[], files: string[] }?
function M.scan(dir)
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return nil
  end
  local out = { dirs = {}, files = {} }
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if kind == "link" then
      local st = vim.uv.fs_stat(dir .. "/" .. name)
      kind = st and st.type or "file"
    end
    table.insert(kind == "directory" and out.dirs or out.files, name)
  end
  local function by_name(a, b)
    return a:lower() < b:lower()
  end
  table.sort(out.dirs, by_name)
  table.sort(out.files, by_name)
  return out
end

---@param m table
---@param dir string
---@return { dirs: string[], files: string[] }?
local function listing(m, dir)
  if m.ls[dir] == nil then
    m.ls[dir] = M.scan(dir) or false
  end
  return m.ls[dir] or nil
end

---@param name string
---@param hidden boolean
---@return boolean
local function shown(name, hidden)
  return hidden or name:sub(1, 1) ~= "."
end

--- The list (pure over m.dir, m.hidden, m.filter and the listings read)
---@param m table
---@return table[]
function M.rows(m)
  local rows = { { title = vim.fn.fnamemodify(m.dir, ":~") }, { spacer = true } }
  local ls = listing(m, m.dir)
  if not ls then
    rows[#rows + 1] = { note = "cannot read this folder" }
    return rows
  end
  local n = 0
  for _, name in ipairs(ls.dirs) do
    if shown(name, m.hidden) and (m.filter == "" or name:lower():find(m.filter:lower(), 1, true)) then
      n = n + 1
      rows[#rows + 1] = { dir = m.dir .. "/" .. name, name = name }
    end
  end
  if n == 0 then
    rows[#rows + 1] = { note = m.filter ~= "" and "no folder matches" or "no folders here" }
  end
  return rows
end

function M.selectable(row)
  return row.dir ~= nil
end

---@param row table
---@return MarketLine
function M.list_line(row)
  if row.title then
    return { { "  " .. row.title, modal.hl.key } }
  elseif row.spacer then
    return { { "" } }
  elseif row.note then
    return { { "    " .. row.note, modal.hl.muted } }
  end
  local git = vim.uv.fs_stat(row.dir .. "/.git") ~= nil
  return {
    { git and "  ● " or "    ", modal.hl.mark },
    { row.name .. "/", modal.hl.file },
    { git and "  git" or "", modal.hl.muted },
  }
end

---@param m table
---@param row table?
---@param width integer
---@return MarketLine[]
function M.pane(m, row, width)
  if not (row and row.dir) then
    return {}
  end
  local out = {}
  if vim.uv.fs_stat(row.dir .. "/.git") then
    -- a git project: branch, commit, stack and README, like the picker's pane (git read in the background)
    out = picker.pane(m, { project = { dir = row.dir, pinned = projects.pinned(row.dir) } }, width)
    out[#out + 1] = { { "" } }
  else
    out[1] = { { "  " .. row.name, "GuiPickerTitle" } }
    out[2] = { { "  " .. vim.fn.fnamemodify(row.dir, ":~"), "GuiPickerDim" } }
    out[3] = { { "" } }
  end
  local ls = listing(m, row.dir)
  if not ls then
    out[#out + 1] = { { "  cannot read this folder", "GuiPickerDim" } }
    return out
  end
  local count = 0
  for _, name in ipairs(ls.dirs) do
    if shown(name, m.hidden) then
      count = count + 1
      if count <= M.PREVIEW then
        out[#out + 1] = { { "  " .. name .. "/", "GuiPickerText" } }
      end
    end
  end
  for _, name in ipairs(ls.files) do
    if shown(name, m.hidden) then
      count = count + 1
      if count <= M.PREVIEW then
        out[#out + 1] = { { "  " .. name, "GuiPickerDim" } }
      end
    end
  end
  if count > M.PREVIEW then
    out[#out + 1] = { { ("  … %d more"):format(count - M.PREVIEW), "GuiPickerDim" } }
  elseif count == 0 then
    out[#out + 1] = { { "  empty", "GuiPickerDim" } }
  end
  return out
end

function M.summary(m)
  local ls = listing(m, m.dir)
  local n = ls and #vim.tbl_filter(function(name)
    return shown(name, m.hidden)
  end, ls.dirs) or 0
  return {
    {
      {
        ("  %d folder%s%s"):format(n, n == 1 and "" or "s", m.hidden and " · hidden shown" or ""),
        modal.hl.muted,
      },
    },
  }
end

function M.hints(_, mode)
  if mode == "pane" then
    return { { "h ← Esc", "back" }, { "⏎", "open as project" } }
  end
  return {
    { "↑↓ jk", "move" },
    { "h ←", "up" },
    { "l →", "in" },
    { "⏎", "open" },
    { "o", "new window" },
    { "p", "pin" },
    { ".", "hidden" },
    { "~", "home" },
    { "/", "filter" },
  }
end

--- Goes to `dir`, with the cursor on `select` (a folder inside it) when given.
---@param m table
---@param dir string
---@param select string?
function M.go(m, dir, select)
  dir = projects.normalize(dir)
  if not listing(m, dir) then
    return vim.notify("Leader: cannot read " .. dir, vim.log.levels.WARN)
  end
  m.dir, m.filter = dir, ""
  market.refresh(m)
  local at = 1
  for i, r in ipairs(m.rows) do
    if r.dir and (r.dir == select or (not select and at == 1)) then
      at = i
      break
    end
  end
  if at == 1 then
    for i, r in ipairs(m.rows) do
      if r.dir then
        at = i
        break
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, m.wins.list, { at, 0 })
  market.refresh(m, true)
end

function M.up(m)
  local parent = vim.fs.dirname(m.dir)
  if parent and parent ~= m.dir then
    M.go(m, parent, m.dir)
  end
end

function M.into(m, row)
  if row and row.dir then
    M.go(m, row.dir)
  end
end

--- Opens the browser.
---@param start string? the folder to show (default: the one above the current project)
function M.open(start)
  local cwd = projects.normalize(vim.uv.cwd() or "~")
  local home = projects.normalize "~"
  local dir = projects.normalize(start or (cwd ~= home and vim.fs.dirname(cwd)) or home)
  local def = {
    title = "Open a folder",
    rows = M.rows,
    selectable = M.selectable,
    list_line = M.list_line,
    pane = M.pane,
    summary = M.summary,
    hints = M.hints,
    summary_rows = 3,
    hjkl = true,
    initial = function(m)
      for i, r in ipairs(m.rows) do
        if r.dir == m.select then
          return i
        end
      end
    end,
    -- a click goes in (⏎ is what opens the project)
    read = function(m, row)
      M.into(m, row)
    end,
    help = {
      { "h ←", "go up a folder" },
      { "l → / click", "go into the folder" },
      { "⏎", "open the folder as the project" },
      { ".", "show hidden folders" },
      { "~", "go to your home folder" },
    },
    keys = {
      list = {
        { { "h", "<Left>", "<BS>" }, M.up, "Up a folder" },
        { { "l", "<Right>" }, M.into, "Into the folder" },
        {
          "<CR>",
          function(m, row)
            if row and row.dir then
              picker.enter_dir(m, row.dir, false)
            end
          end,
          "Open as project",
        },
        {
          "o",
          function(m, row)
            if row and row.dir then
              picker.enter_dir(m, row.dir, true)
            end
          end,
          "Open in a new window",
        },
        {
          "p",
          function(m, row)
            if row and row.dir then
              projects.pin(row.dir, not projects.pinned(row.dir))
              m.info[row.dir] = nil
              market.refresh(m, true)
            end
          end,
          "Pin project",
        },
        {
          ".",
          function(m, row)
            m.hidden = not m.hidden
            m.select = row and row.dir
            market.refresh(m)
            M.go(m, m.dir, m.select)
          end,
          "Hidden folders",
        },
        {
          "~",
          function(m)
            M.go(m, home)
          end,
          "Home folder",
        },
      },
    },
  }
  local m = market.new(def, { dir = dir, hidden = false, ls = {}, info = {}, select = cwd })
  if not m then
    return
  end
  -- the project you are in is the row to start on, when it is in this folder
  M.go(m, dir, cwd)
  return m
end

return M
