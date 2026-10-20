-- ── Desktop app ──────────────────────────────────────────────────────────────
-- Neovim inside the `leader` window (app/): the app sets vim.g.leader_gui (and
-- the RPC channel, vim.g.leader_gui_channel) before the config loads and serves
-- the clipboard itself. Here only what the config decides for it (settings.gui):
-- the font, what the app bar says and what its buttons do (`action`: home,
-- history, welcome, theme, agent…), and the guided setup (gui/wizard.lua, with the
-- install checks of gui/checks.lua). The bar is minimal: the current file's
-- path, every part clickable (a folder opens Telescope inside it, the file shows
-- it in the tree), and on the right only what the statusline does NOT already
-- show (recording, the file's git changes, LSP, indent, unusual encodings).
-- Sent only when something changed, with the flat design's colors.
local settings = require "core.settings"

local M = {}

local last ---@type string? what was sent last (JSON), to skip identical updates
local queued = false
---@type { dir: string?, file: string? }[] what each part of the path opens, in the order the app numbers them
local targets = {}
---@type { path: string[], file: string, targets: table, buf: integer }? the last real file (special buffers keep it)
local kept

-- ── Activity: what is running right now, for the bar's spinner and progress line ──
---@type table<string, { name: string, title: string?, message: string?, percent: number?, at: number }>
local running = {}
---@type { text: string, until_ms: number }? a short "done" after something finished
local finished
--- install checks that still fail (gui/checks.lua), counted for the bar's "N to finish" chip
local unfinished = 0

local ticker

--- Long work says how long it has been going (a bar that only says "loading packages" looks hung): every 5 s the
--- bar is redrawn while something is running.
local function tick()
  if ticker then
    return
  end
  ticker = vim.uv.new_timer()
  ticker:start(
    5000,
    5000,
    vim.schedule_wrap(function()
      if next(running) == nil then
        ticker:stop()
        ticker:close()
        ticker = nil
      else
        M.update()
      end
    end)
  )
end

---@param ms integer
---@return string "12s", "2m 05s"
function M.elapsed(ms)
  local s = math.floor(ms / 1000)
  return s < 60 and (s .. "s") or ("%dm %02ds"):format(math.floor(s / 60), s % 60)
end

---@param key string
---@param name string
---@param title string?
---@param message string?
---@param percent number?
local function begin(key, name, title, message, percent)
  local now = vim.uv.now()
  running[key] = {
    name = name,
    title = title,
    message = message,
    percent = percent,
    at = now,
    since = (running[key] or {}).since or now,
  }
  tick()
  M.update()
end

---@param key string
---@param text string? what to say for a moment once it is done (nil = nothing)
local function done(key, text)
  running[key] = nil
  if text then
    finished = { text = text, until_ms = vim.uv.now() + 1600 }
    vim.defer_fn(M.update, 1700)
  end
  M.update()
end

---@return table? { text, percent?, done? } the newest thing running, else what just finished
local function activity()
  local newest
  for _, r in pairs(running) do
    if not newest or r.at > newest.at then
      newest = r
    end
  end
  if newest then
    local parts = { newest.name }
    if newest.title and newest.title ~= "" then
      parts[#parts + 1] = newest.title
    end
    local message, percent = newest.message, newest.percent
    local tracked = newest.name == "language tools" and require("gui.progress").current
    if tracked and tracked.active then
      -- "7/9 · codelldb 12.7 MB 31 KB/s · 6m 40s": what is going on, in numbers, with the bar filling
      message, percent = require("gui.progress").status_text(tracked, os.time())
      newest = vim.tbl_extend("force", newest, { percent = percent })
    end
    if message and message ~= "" and #message < 90 then
      parts[#parts + 1] = message
    end
    local waited = vim.uv.now() - (newest.since or newest.at)
    if waited >= 10000 then
      parts[#parts + 1] = M.elapsed(waited)
    end
    -- the first load of a Go project that uses cgo (sqlite, …) compiles it: minutes once, seconds after
    if waited >= 30000 and newest.name == "gopls" then
      parts[#parts + 1] = "big projects take minutes the first time"
    end
    return { text = table.concat(parts, " · "), percent = newest.percent }
  end
  if finished and vim.uv.now() < finished.until_ms then
    return { text = finished.text, done = true }
  end
end

---@param t FlatTokens
---@param buf integer
---@param show table
---@return table[]
local function chips(t, buf, show)
  local out = {}
  local function add(text, fg, bg, gap, action)
    out[#out + 1] = { text = text, fg = fg, bg = bg, gap = gap, action = action }
  end
  -- a newer Leader (lua/update): one click shows what changed and updates on request
  local offered, latest = require("update").offer()
  if show.update ~= false and offered then
    add("\u{f062} " .. latest, t.green, nil, 2, "update")
  end
  if show.setup ~= false and unfinished > 0 then
    -- something is still missing: one click opens the welcome screen, Enter there installs it
    add(("\u{f071} %d to finish"):format(unfinished), t.yellow, nil, 2, "welcome")
  end
  local rec = vim.fn.reg_recording()
  if show.recording ~= false and rec ~= "" then
    add("REC @" .. rec, t.on, t.red)
  end
  local git = vim.b[buf].gitsigns_status_dict
  if show.git ~= false and git then
    local first = true
    for _, k in ipairs { { "added", "+", t.green }, { "changed", "~", t.yellow }, { "removed", "-", t.red } } do
      local n = git[k[1]] or 0
      if n > 0 then
        add(k[2] .. n, k[3], nil, first and 2 or 1)
        first = false
      end
    end
  end
  if show.lsp then
    local names = {}
    for _, c in ipairs(vim.lsp.get_clients { bufnr = buf }) do
      names[#names + 1] = c.name
    end
    if #names > 0 then
      add(table.concat(names, " "), t.dim)
    end
  end
  local bo = vim.bo[buf]
  if bo.buftype == "" then
    if show.indent then
      add(bo.expandtab and ("␣" .. vim.fn.shiftwidth()) or ("⇥" .. bo.tabstop), t.dim)
    end
    -- only when it is not the usual: utf-8 and unix line endings say nothing
    if show.format ~= false and bo.fileencoding ~= "" and bo.fileencoding ~= "utf-8" then
      add(bo.fileencoding, t.yellow)
    end
    if show.format ~= false and bo.fileformat ~= "unix" then
      add(bo.fileformat, t.yellow)
    end
  end
  return out
end

---@return table
function M.state()
  local cfg = settings.gui.appbar or {}
  local t = require("ui.flat.palette").current()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) or ""
  local rel = name ~= "" and vim.fn.fnamemodify(name, ":~:.") or ""
  local path, file = {}, ""
  if vim.bo[buf].filetype == "nvdash" then
    -- the start screen: nothing to locate
    targets = {}
  elseif rel == "" and kept then
    -- Telescope, the tree, a terminal…: keep showing the file you were on
    path, file, targets = kept.path, kept.file, kept.targets
  elseif rel ~= "" then
    targets = {}
    path = vim.split(vim.fs.dirname(rel) == "." and "" or vim.fs.dirname(rel), "/", { trimempty = true })
    file = vim.fs.basename(rel)
    -- each folder opens itself: walk up from the file so "~" and absolute paths resolve too
    local dir = vim.fs.dirname(name)
    for i = #path, 1, -1 do
      targets[i] = { dir = dir }
      dir = vim.fs.dirname(dir)
    end
    targets[#path + 1] = { file = name }
    kept = { path = path, file = file, targets = targets, buf = buf }
  end
  local toolbar = require "gui.toolbar"
  local buttons = cfg.buttons or {}
  local left, right = toolbar.tools(buttons)
  return {
    enabled = cfg.enabled ~= false,
    controls = cfg.controls or "right",
    mark = buttons.mark ~= false,
    left = left,
    right = right,
    activity = cfg.activity ~= false and activity() or nil,
    height = cfg.height or 1.5,
    padding = settings.gui.padding or {},
    -- what the app keeps of the window when it closes (it reopens with that)
    window = {
      size = (settings.gui.window or {}).remember_size ~= false,
      position = (settings.gui.window or {}).remember_position ~= false,
      maximized = (settings.gui.window or {}).remember_maximized ~= false,
    },
    path = path,
    file = file,
    modified = file ~= "" and kept ~= nil and vim.api.nvim_buf_is_valid(kept.buf) and vim.bo[kept.buf].modified,
    chips = chips(
      t,
      (rel == "" and kept and vim.api.nvim_buf_is_valid(kept.buf)) and kept.buf or buf,
      toolbar.chips(cfg.show or {})
    ),
    colors = {
      fg = t.fg,
      dim = t.dim,
      faint = t.faint,
      mark = t.green, -- the brand's dots (brand/dots.js)
      accent = t.aqua,
      green = t.green,
      yellow = t.yellow,
      red = t.red,
      on = t.on,
    },
  }
end

--- A part of the path was clicked in the app bar (0-based: folders first, then the file).
---@param index integer
function M.click(index)
  local target = targets[index + 1]
  if not target then
    return
  end
  if target.file then
    local ok, api = pcall(require, "nvim-tree.api")
    if ok then
      return api.tree.find_file { buf = target.file, open = true, focus = true }
    end
    return
  end
  local ok, builtin = pcall(require, "telescope.builtin")
  if ok then
    return builtin.find_files { cwd = target.dir, prompt_title = vim.fn.fnamemodify(target.dir, ":~:.") }
  end
  vim.cmd.edit(vim.fn.fnameescape(target.dir))
end

--- Puts the cursor in a normal editing window (from the tree, a float or a picker).
local function editing_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if
      vim.api.nvim_win_get_config(win).relative == ""
      and (vim.bo[buf].buftype == "" or vim.bo[buf].filetype == "nvdash")
    then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end

--- Asks the window for what only it can do (fullscreen, zoom, a new window…).
---@param name string
local function window(name)
  return function()
    if vim.g.leader_gui_channel then
      vim.rpcnotify(vim.g.leader_gui_channel, "leader_window", name)
    end
  end
end

---@param keys string
local function feed(keys)
  return function()
    vim.api.nvim_feedkeys(vim.keycode(keys), "m", false)
  end
end

---@param cmd string
local function ex(cmd)
  return function()
    editing_window()
    pcall(vim.cmd, cmd)
  end
end

---@return boolean inside a git repository (the Git menu only exists there, like `<leader>G`)
local function in_repo()
  return vim.fs.find(".git", { upward = true, path = vim.uv.cwd() })[1] ~= nil
end

--- The app menu (Leader's N in the bar, F10), laid out like Zed's: every item types the config's own keys (so it
--- does exactly what they do, and shows them) or runs a command. Built on each opening (Git only inside a repo).
---@return GuiMenuItem[]
--- A setting of the settings panel as a submenu: its choices, the current one dotted (saved like the panel saves).
---@param label string
---@param id string
local function pref_menu(label, id)
  local prefs = require "prefs"
  local item = prefs.find(id)
  if not item then
    return { label = label, hint = "settings", keys = "<leader>Sp" }
  end
  local now = prefs.value(item)
  local sub = {}
  for _, c in ipairs(prefs.choices(item)) do
    sub[#sub + 1] = {
      label = c.label,
      current = now == c.value or (c.value == true and now == nil),
      run = function()
        prefs.set(item, c.value)
      end,
    }
  end
  return { label = label, hint = prefs.text(item), items = sub }
end

function M.app_menu()
  local projects = require "gui.projects"
  local offered, latest = require("update").offer()
  local picker = function()
    require("gui.picker").open()
  end
  local browse = function()
    require("gui.browse").open()
  end
  local menu = {
    {
      label = "File",
      items = {
        { label = "New File", keys = "<leader>Fn" },
        { label = "New Folder", keys = "<leader>FN" },
        { sep = true },
        { label = "Open File…", keys = "<leader>ff" },
        { label = "Open Recent", hint = "Ctrl+Shift+R", run = M.actions.history },
        { label = "Open Project…", hint = "Ctrl+Shift+O", run = picker },
        { label = "Browse Folders…", run = browse },
        { label = "Open Path…", run = projects.ask },
        { sep = true },
        { label = "Save", keys = "<C-s>" },
        { label = "Save All", hint = ":wa", run = ex "wall" },
        { sep = true },
        { label = "Rename…", keys = "<leader>Fr" },
        { label = "Move…", keys = "<leader>Fm" },
        { label = "Duplicate", keys = "<leader>Fc" },
        { label = "Delete", keys = "<leader>Fx" },
        { label = "Undo Delete", keys = "<leader>Fu" },
        { label = "Copy Path", keys = "<leader>Fy" },
        { sep = true },
        { label = "Close File", keys = "<leader>q" },
        { label = "Close Project", hint = "home", run = M.actions.home },
      },
    },
    {
      label = "Edit",
      items = {
        { label = "Undo", keys = "<C-z>" },
        { label = "Redo", keys = "<C-y>" },
        { label = "Undo History", keys = "<leader>uu" },
        { label = "Yank History", keys = "<leader>uy" },
        { sep = true },
        { label = "Copy Whole File", keys = "<C-c>" },
        { label = "Paste", hint = "Ctrl+Shift+V", run = ex 'normal! "+p' },
        { sep = true },
        { label = "Find in File", hint = "/", run = feed "/" },
        { label = "Find in Project", keys = "<leader>fw" },
        { label = "Replace in Project", keys = "<leader>fr" },
        { sep = true },
        { label = "Toggle Comment", keys = "<leader>/" },
        { label = "Format File", keys = "<leader>fm" },
        { label = "Move Line Up", keys = "<M-k>" },
        { label = "Move Line Down", keys = "<M-j>" },
      },
    },
    {
      label = "Selection",
      items = {
        { label = "Select All", hint = "ggVG", run = feed "ggVG" },
        { label = "Select Line", hint = "V", run = feed "V" },
        { label = "Expand by Syntax", hint = "S", run = feed "S" },
        { sep = true },
        { label = "Add Cursor Above", keys = "<C-Up>" },
        { label = "Add Cursor Below", keys = "<C-Down>" },
        { label = "Add Next Match", keys = "<M-n>" },
        { label = "Add All Matches", keys = "<M-a>" },
      },
    },
    {
      label = "View",
      items = {
        { label = "Command Palette…", hint = "Ctrl+Shift+P", run = M.palette },
        {
          label = "Customize Toolbar…",
          hint = "right click",
          run = function()
            M.actions.customize()
          end,
        },
        { sep = true },
        { label = "File Tree", keys = "<C-n>" },
        { label = "Outline", hint = ":AerialToggle", run = ex "AerialToggle" },
        { label = "Problems", keys = "<leader>xx" },
        { label = "Terminal", keys = "<M-i>" },
        { label = "Terminal Below", keys = "<M-h>" },
        { sep = true },
        { label = "Fullscreen", hint = "F11", run = window "fullscreen" },
        { label = "Zoom In", hint = "Ctrl+=", run = window "zoom_in" },
        { label = "Zoom Out", hint = "Ctrl+-", run = window "zoom_out" },
        { label = "Reset Zoom", hint = "Ctrl+0", run = window "zoom_reset" },
        { sep = true },
        {
          label = "Theme…",
          run = function()
            M.actions.theme(0)
          end,
        },
        { label = "Light / Dark", keys = "<leader>St" },
        { label = "Fold All", keys = "<leader>za" },
        { label = "Unfold All", keys = "<leader>ze" },
      },
    },
    {
      label = "Go",
      items = {
        { label = "Go to File…", keys = "<leader>ff" },
        { label = "Go to Open File…", keys = "<leader>fb" },
        { label = "Go to Symbol in Project…", keys = "<leader>fs" },
        { label = "Go to Symbol in File…", hint = "gO", run = feed "gO" },
        { sep = true },
        {
          label = "Definition",
          hint = "gd",
          run = function()
            vim.lsp.buf.definition()
          end,
        },
        { label = "References", hint = "grr", run = feed "grr" },
        { label = "Implementation", hint = "gri", run = feed "gri" },
        { sep = true },
        { label = "Next Problem", hint = "]d", run = feed "]d" },
        { label = "Previous Problem", hint = "[d", run = feed "[d" },
        { label = "Next Function", hint = "]f", run = feed "]f" },
        { label = "Previous Function", hint = "[f", run = feed "[f" },
        { sep = true },
        { label = "Back", keys = "<C-o>" },
        { label = "Forward", keys = "<C-i>" },
        { label = "Pinned Files", keys = "<leader>hm" },
      },
    },
    {
      label = "Run",
      items = {
        { label = "Run Task…", keys = "<leader>Rr" },
        { label = "Run Default Task", keys = "<leader>Rd" },
        { label = "Run Last Task", keys = "<leader>Rl" },
        { label = "Stop Task", keys = "<leader>Rs" },
        { label = "Task Output", keys = "<leader>Ro" },
        { sep = true },
        { label = "Create a Makefile…", keys = "<leader>Rc" },
      },
    },
    {
      label = "Git",
      when = in_repo,
      items = {
        { label = "Commit…", keys = "<leader>Gc" },
        { label = "Commit with AI Message", keys = "<leader>GM" },
        { sep = true },
        { label = "Changes (Diff)", keys = "<leader>Gd" },
        { label = "File History", keys = "<leader>Gf" },
        { label = "Blame", keys = "<leader>Gb" },
        { sep = true },
        { label = "Branches…", run = ex "Telescope git_branches" },
        { label = ".gitignore…", keys = "<leader>Gi" },
        { label = "Changelog", keys = "<leader>GRc" },
        { label = "All Git Keys…", keys = "<leader>G" },
      },
    },
    {
      label = "Agent",
      items = {
        { label = "Ask…", keys = "<leader>aa" },
        { label = "Explain", keys = "<leader>ae" },
        { label = "Fix", keys = "<leader>af" },
        { label = "Review", keys = "<leader>ar" },
        { label = "Refactor", keys = "<leader>aR" },
        { label = "Write Docs", keys = "<leader>ad" },
        { label = "Next Edit", keys = "<leader>an" },
        { sep = true },
        { label = "History", keys = "<leader>ah" },
        { label = "Model…", keys = "<leader>am" },
        { label = "Stop", keys = "<leader>ax" },
        { label = "All Agent Actions…", keys = "<leader>a" },
      },
    },
    {
      label = "Window",
      items = {
        { label = "New Window", hint = "Ctrl+Shift+N", run = window "new_window" },
        { label = "Minimize", hint = "Ctrl+Shift+M", run = window "minimize" },
        { label = "Maximize", hint = "Ctrl+Shift+Enter", run = window "maximize" },
        { label = "Fullscreen", hint = "F11", run = window "fullscreen" },
        { sep = true },
        { label = "Split Right", hint = ":vsplit", run = ex "vsplit" },
        { label = "Split Down", hint = ":split", run = ex "split" },
        { label = "Close Split", hint = "Ctrl+W c", run = ex "close" },
        { sep = true },
        pref_menu("On Start", "gui.window.on_start"),
        pref_menu("Frame", "gui.appbar.enabled"),
        pref_menu("Remember Size", "gui.window.remember_size"),
        pref_menu("Remember Position", "gui.window.remember_position"),
        pref_menu("Reopen Maximized", "gui.window.remember_maximized"),
      },
    },
    {
      label = "Help",
      items = {
        { label = "Welcome & Checks", hint = "Ctrl+Shift+W", run = M.actions.welcome },
        { label = "Every Menu", keys = "<leader>" },
        { label = "All Keys", hint = ":NvCheatsheet", run = ex "NvCheatsheet" },
        { label = "Settings", keys = "<leader>Sp" },
        { label = "Check Health", hint = ":checkhealth", run = ex "checkhealth" },
        { sep = true },
        { label = "What's New…", run = M.actions.update },
        {
          label = "Check for Updates",
          run = function()
            require("update").check { force = true, done = M.actions.update }
          end,
        },
        { label = "About Leader", run = M.about },
      },
    },
    { sep = true },
    { label = "Command Palette…", hint = "Ctrl+Shift+P", run = M.palette },
    { label = "Open Project…", hint = "Ctrl+Shift+O", run = picker },
    { label = "Home", hint = "Ctrl+Shift+H", run = M.actions.home },
    { sep = true },
    { label = "Quit", hint = ":qa", run = ex "confirm qall" },
  }
  if offered then
    -- the logo's menu leads with it
    table.insert(menu, 1, { label = "★ Update to " .. latest .. "…", run = M.actions.update })
    table.insert(menu, 2, { sep = true })
  end
  return menu
end

--- Everything the menus can do plus every key of the config that says what it does, in one search (Telescope).
function M.palette()
  local ok = pcall(require, "telescope")
  if not ok then
    return
  end
  local menu = require "gui.menu"
  local pickers, finders, conf =
    require "telescope.pickers", require "telescope.finders", require("telescope.config").values
  local actions, action_state = require "telescope.actions", require "telescope.actions.state"
  local entries, seen = {}, {}
  for _, e in ipairs(menu.flatten(M.app_menu())) do
    local hint = e.item.hint or (e.item.keys and menu.describe(e.item.keys)) or ""
    entries[#entries + 1] = { text = e.path, hint = hint, item = e.item }
    if e.item.keys then
      seen[vim.keycode(e.item.keys)] = true
    end
  end
  for _, m in ipairs(vim.api.nvim_get_keymap "n") do
    local desc = m.desc or ""
    -- the config's own keys say what they do in 2+ words, section first ("Go run"); Neovim's built-ins are skipped
    if desc:find " " and not desc:find "^:help" and not seen[vim.keycode(m.lhs)] then
      local lhs = m.lhs:gsub("^ ", "<leader>")
      entries[#entries + 1] =
        { text = desc:sub(1, 1):upper() .. desc:sub(2), hint = menu.describe(lhs), item = { keys = lhs } }
    end
  end
  local width = 0
  for _, e in ipairs(entries) do
    width = math.max(width, vim.fn.strdisplaywidth(e.text))
  end
  pickers
    .new({}, {
      prompt_title = "Command Palette",
      finder = finders.new_table {
        results = entries,
        entry_maker = function(e)
          return {
            value = e,
            ordinal = e.text .. " " .. e.hint,
            display = e.text .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(e.text) + 3, 2)) .. e.hint,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt)
        actions.select_default:replace(function()
          local sel = action_state.get_selected_entry()
          actions.close(prompt)
          if sel then
            vim.schedule(function()
              menu.activate(sel.value.item)
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

--- The version of the config and of the app, and where they live.
function M.about()
  local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.stdpath "config"), ":h")
  local f = io.open(root .. "/VERSION")
  local version = f and vim.trim(f:read "*a") or "dev"
  if f then
    f:close()
  end
  -- the brand's N (brand/dots.js "classicN": 5 x 7 dots), then what this is
  local N = { "X...X", "XX..X", "X.X.X", "X..XX", "X...X", "X...X", "X...X" }
  local lines = { { { "" } } } -- the dialog marks its first line: let that be the empty one
  for _, row in ipairs(N) do
    local dots = row:gsub(".", function(c)
      return c == "X" and "● " or "  "
    end)
    lines[#lines + 1] = { { "   " .. dots, "GuiWizardOn" } }
  end
  lines[#lines + 1] = { { "" } }
  lines[#lines + 1] = { { "Leader " .. version .. "  ·  app " .. (vim.g.leader_gui_version or "?"), "NvModalKey" } }
  lines[#lines + 1] = { { "Neovim, for working.", "NvModalMuted" } }
  lines[#lines + 1] = { { "" } }
  lines[#lines + 1] = "Neovim " .. tostring(vim.version())
  if (vim.g.leader_gui_gpu or "") ~= "" then
    lines[#lines + 1] = (vim.g.leader_gui_gpu:gsub(",.*$", "")) -- the adapter and its API, not the surface format
  end
  lines[#lines + 1] = "Config: " .. vim.fn.fnamemodify(root, ":~")
  lines[#lines + 1] = { { "sazardev.github.io/leader", "NvModalMuted" } }
  require("utils.modal").confirm(lines, { title = "About Leader", confirm = "Close" }, function() end)
end

--- The projects menu (the project's name in the bar): the remembered ones, newest first, then the ways to open
--- or start another.
---@return GuiMenuItem[]
function M.projects_menu()
  local projects = require "gui.projects"
  local picker = require "gui.picker"
  local cwd = projects.normalize(vim.uv.cwd() or "")
  local items = {}
  -- pinned first, then the newest
  local list = projects.list()
  table.sort(list, function(a, b)
    if (a.pinned == true) ~= (b.pinned == true) then
      return a.pinned == true
    end
    return (a.at or 0) > (b.at or 0)
  end)
  for i, p in ipairs(list) do
    if i > 12 then
      break
    end
    items[#items + 1] = {
      label = (p.pinned and "★ " or "") .. vim.fn.fnamemodify(p.dir, ":t"),
      detail = vim.fn.fnamemodify(vim.fs.dirname(p.dir), ":~"),
      current = p.dir == cwd,
      run = function()
        projects.switch(p.dir)
      end,
    }
  end
  items[#items + 1] = { sep = true }
  items[#items + 1] = { label = "Open Project…", hint = "Ctrl+Shift+O", run = picker.open }
  items[#items + 1] = {
    label = "Browse Folders…",
    run = function()
      require("gui.browse").open()
    end,
  }
  items[#items + 1] = { label = "Open Path…", run = projects.ask }
  items[#items + 1] = {
    label = "New Project…",
    run = function()
      picker.start "new"
    end,
  }
  items[#items + 1] = {
    label = "Clone Repository…",
    run = function()
      picker.start "clone"
    end,
  }
  return items
end

M.THEMES = {
  dark = {
    "gruvbox",
    "catppuccin",
    "tokyonight",
    "onedark",
    "rosepine",
    "kanagawa",
    "nord",
    "everforest",
    "github_dark",
    "vesper",
    "oxocarbon",
    "nightfox",
  },
  light = { "gruvbox_light", "catppuccin-latte", "github_light", "rosepine-dawn", "one_light", "everforest_light" },
}

--- The theme menu (the bar's brush): the toggle, the terminal's theme, a short list of dark and light ones, previewed
--- while the pointer or the cursor is on them (closing without a choice puts yours back), and the whole catalog.
---@return GuiMenuItem[] items, fun() revert
function M.theme_menu()
  local appearance = require "appearance"
  local before = appearance.current()
  local function list(names)
    local out = {}
    for _, name in ipairs(names) do
      if #vim.api.nvim_get_runtime_file("lua/base46/themes/" .. name .. ".lua", false) > 0 then
        out[#out + 1] = {
          label = name,
          current = name == before,
          preview = function()
            pcall(appearance.use, name)
          end,
          run = function()
            pcall(appearance.use, name)
            require("utils.log").info("Theme: " .. name)
          end,
        }
      end
    end
    return out
  end
  local items = {
    { label = "Light / Dark", keys = "<leader>St" },
    {
      label = "Terminal Theme",
      current = before == appearance.TERMINAL,
      run = function()
        pcall(appearance.use, appearance.TERMINAL)
      end,
    },
    { sep = true },
    { label = "Dark", items = list(M.THEMES.dark) },
    { label = "Light", items = list(M.THEMES.light) },
    { sep = true },
    { label = "All Themes…", run = ex "lua require('gui.themes').open()" },
  }
  return items, function()
    if appearance.current() ~= before then
      pcall(appearance.use, before)
    end
  end
end

--- The agent menu (the bar's bolt): every agent this machine has, each with its models (a dot on the one in use),
--- then the model and effort panel and the setup that finds or installs one.
---@return GuiMenuItem[]
function M.agent_menu()
  local ok, backends = pcall(require, "agent.backends")
  local items = {}
  if ok then
    local selection = require "agent.selection"
    local cur = selection.current()
    for _, name in ipairs(backends.names()) do
      local b = backends.get(name)
      if b and backends.is_available(name) then
        local models, done = {}, false
        pcall(b.models, function(list)
          models, done = list or {}, true
        end)
        vim.wait(800, function()
          return done
        end, 20)
        local sub = {}
        for _, mdl in ipairs(models) do
          local id = mdl.id or mdl.name or tostring(mdl)
          sub[#sub + 1] = {
            label = id,
            current = cur ~= nil and cur.backend == name and cur.model == id,
            run = function()
              selection.set(name, id)
              require("utils.log").info(("Agent: %s/%s"):format(name, id))
              M.update()
            end,
          }
        end
        if #sub == 0 then
          sub[1] = { label = "no models listed", hint = "Space a m" }
        end
        items[#items + 1] = {
          label = name,
          detail = cur and cur.backend == name and (cur.model or "") or "",
          current = cur ~= nil and cur.backend == name,
          items = sub,
        }
      end
    end
  end
  if #items == 0 then
    items[1] = { label = "No agent on this machine yet", hint = "" }
  end
  vim.list_extend(items, {
    { sep = true },
    { label = "Model & Effort…", keys = "<leader>am" },
    {
      label = "Find or Install an Agent…",
      run = function()
        require("agent.setup").open()
      end,
    },
    { label = "Set Up Leader…", run = M.actions.welcome },
  })
  return items
end

---@type table<string, fun(col: integer?)>
M.actions = {
  -- the start screen (its buttons: sessions, files, recent files, word, themes…)
  home = function()
    if vim.bo.filetype == "nvdash" then
      return
    end
    editing_window()
    require("ui.start").open()
  end,
  -- recent files of this project, the same list as the start screen's "Recent Files"
  history = function()
    editing_window()
    require("recent").open()
  end,
  welcome = function()
    require("gui.onboarding").open()
  end,
  -- what is new and the update (lua/update)
  update = function()
    require("update.panel").open()
  end,
  menu = function(col)
    require("gui.menu").open(M.app_menu(), { col = col })
  end,
  palette = function()
    M.palette()
  end,
  open_project = function()
    require("gui.picker").open()
  end,
  theme = function(col)
    local items, revert = M.theme_menu()
    require("gui.menu").open(items, { col = col, revert = revert })
  end,
  agent = function(col)
    require("gui.menu").open(M.agent_menu(), { col = col })
  end,
  tree = function()
    pcall(vim.cmd, "NvimTreeToggle")
    M.update()
  end,
  terminal = feed "<M-i>",
  problems = feed "<leader>xx",
  settings = feed "<leader>Sp",
  customize = function()
    require("gui.toolbar").customize(M.update)
  end,
  projects = function(col)
    require("gui.menu").open(M.projects_menu(), { col = col })
  end,
}

--- A button of the app bar or a window shortcut (the app calls it by name, with the column under the button).
---@param name string
---@param col integer?
function M.action(name, col)
  local f = M.actions[name]
  if f then
    f(col)
  end
end

--- Runs the install checks again (off the critical path) and updates the bar's "to finish" chip.
function M.recheck()
  vim.defer_fn(function()
    local ok, list = pcall(function()
      return require("gui.checks").run()
    end)
    if ok then
      unfinished = require("gui.checks").missing(list)
      M.update()
    end
  end, 50)
end

--- Sends the bar's state on the next tick (events often come in bursts), only if it changed.
function M.update()
  if queued then
    return
  end
  queued = true
  vim.schedule(function()
    queued = false
    local ok, state = pcall(M.state)
    if not ok then
      return
    end
    local json = vim.json.encode(state)
    if json ~= last and vim.g.leader_gui_channel then
      last = json
      pcall(vim.rpcnotify, vim.g.leader_gui_channel, "leader_appbar", state)
    end
  end)
end

--- Opens what a later `leader --reuse …` handed to this window: a folder becomes the project (its session back), files
--- are edited, the last one stays in front.
---@param paths string[] absolute
function M.open_external(paths)
  local dir
  local files = {}
  for _, p in ipairs(paths or {}) do
    if vim.fn.isdirectory(p) == 1 then
      dir = p
    else
      files[#files + 1] = p
    end
  end
  if dir then
    require("gui.projects").switch(dir)
  end
  for _, f in ipairs(files) do
    pcall(vim.cmd.edit, vim.fn.fnameescape(f))
  end
end

local released = false

--- Tells the app the first screen is complete: it draws nothing until now, so the window opens on the real editor and
--- not on Neovim's black default. The redraw first, so the content is on the wire before the notice (same channel, in
--- order). Once; the app has a deadline in case this never comes.
function M.release()
  if released or not vim.g.leader_gui_channel then
    return
  end
  released = true
  pcall(vim.cmd, "redraw")
  pcall(vim.rpcnotify, vim.g.leader_gui_channel, "leader_ready")
end

function M.setup()
  if not vim.g.leader_gui then
    return
  end
  -- as early as possible: from here on the app waits for `release` before its first frame
  pcall(vim.rpcnotify, vim.g.leader_gui_channel, "leader_hold")
  -- Neovim's own default is a generic list (Source Code Pro, …): only an explicit choice wins over ours.
  local default = vim.api.nvim_get_option_info2("guifont", {}).default
  if settings.gui.font and (vim.o.guifont == "" or vim.o.guifont == default) then
    vim.o.guifont = settings.gui.font
  end
  local group = vim.api.nvim_create_augroup("LeaderGui", { clear = true })
  vim.api.nvim_create_autocmd({
    "VimEnter",
    "BufEnter",
    "BufWritePost",
    "BufModifiedSet",
    "DirChanged",
    "LspAttach",
    "LspDetach",
    "FocusGained",
    "ColorScheme",
    "RecordingEnter",
    "RecordingLeave",
    "BufWinEnter", -- the tree opening or closing lights its toolbar button
    "WinClosed",
  }, { group = group, callback = M.update })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "expandtab", "shiftwidth", "tabstop", "fileformat", "fileencoding" },
    callback = M.update,
  })
  vim.api.nvim_create_autocmd(
    "User",
    { group = group, pattern = { "NvThemeReload", "GitSignsUpdate", "LeaderUpdateChecked" }, callback = M.update }
  )

  -- activity: LSP work in progress ($/progress), plugin and language-tool installs, and a save
  vim.api.nvim_create_autocmd("LspProgress", {
    group = group,
    callback = function(ev)
      local p = ev.data and ev.data.params
      local value = p and p.value
      if type(value) ~= "table" then
        return
      end
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      local name = client and client.name or "lsp"
      local key = ("lsp:%s:%s"):format(ev.data.client_id, tostring(p.token))
      if value.kind == "end" then
        done(key, name .. " ready")
      else
        local prev = running[key] or {}
        begin(key, name, value.title or prev.title, value.message, value.percentage)
      end
    end,
  })
  local lazy = {
    LazyInstallPre = "installing plugins",
    LazyUpdatePre = "updating plugins",
    LazySyncPre = "syncing plugins",
    LazyRestorePre = "restoring plugins",
  }
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = vim.list_extend(vim.tbl_keys(lazy), { "LazyInstall", "LazyUpdate", "LazySync", "LazyRestore" }),
    callback = function(ev)
      if lazy[ev.match] then
        begin("lazy", "plugins", (lazy[ev.match]:gsub(" plugins$", "")))
      else
        done("lazy", "plugins up to date")
        M.recheck()
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "MasonToolsStartingInstall", "MasonToolsUpdateCompleted" },
    callback = function(ev)
      if ev.match == "MasonToolsStartingInstall" then
        require("gui.progress").begin_mason()
        begin("mason", "language tools", "installing")
      else
        require("gui.progress").end_mason()
        done("mason", "language tools installed")
        M.recheck()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      if (settings.gui.appbar or {}).activity ~= false and vim.bo[ev.buf].buftype == "" then
        done("save", "saved " .. vim.fn.fnamemodify(ev.file, ":t"))
      end
    end,
  })
  require("gui.projects").setup(group)
  require("gui.mouse").setup(group)
  M.update()
  require("gui.onboarding").setup()
  require("gui.startup").setup()
end

return M
