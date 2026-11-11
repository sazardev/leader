-- ── Sessions (persistence.nvim): helpers for menus and dashboard ──────────────
-- The session file is found and sourced directly (persistence.nvim's naming) so a bare start restores it without
-- loading the plugin: no git subprocess, no lazy-load, no start screen opened and thrown away. The plugin still saves
-- on exit and lists sessions.
local log = require "utils.log"

local M = {}

local SESSION_DIR = vim.fn.stdpath "state" .. "/sessions"

--- Read a small file without the vim.fn round trip.
---@param path string
---@return string?
local function read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

--- The branch persistence would put in the session name (nil for main/master, detached HEAD or no repo), read from
--- .git/HEAD: `git branch --show-current` in a subprocess costs more than the whole lookup.
---@param cwd string
---@return string?
local function branch(cwd)
  local git = cwd .. "/.git"
  local st = vim.uv.fs_stat(git)
  if not st then
    return nil
  end
  local head
  if st.type == "directory" then
    head = git .. "/HEAD"
  else
    -- a worktree: .git is a file with `gitdir: /path/to/.git/worktrees/<name>`
    local gitdir = (read(git) or ""):match "^gitdir:%s*(.-)%s*$"
    if not gitdir or gitdir == "" then
      return nil
    end
    if gitdir:sub(1, 1) ~= "/" and not gitdir:match "^%a:[/\\]" then
      gitdir = cwd .. "/" .. gitdir
    end
    head = gitdir .. "/HEAD"
  end
  local name = (read(head) or ""):match "^ref: refs/heads/(.-)%s*$"
  if name and name ~= "" and name ~= "main" and name ~= "master" then
    return name
  end
end

--- Escape a path the way persistence.nvim names session files.
---@param path string
---@return string
local function escape(path)
  return (path:gsub("[\\/:]+", "%%"))
end

---@return table? persistence
local function persistence()
  local ok, p = pcall(require, "persistence")
  return ok and p or nil
end

--- This folder's session file (the current branch's first, then the base one), without loading persistence.nvim.
---@return string?
function M.file()
  local cwd = vim.fn.getcwd()
  local name = escape(cwd)
  local b = branch(cwd)
  if b then
    local file = SESSION_DIR .. "/" .. name .. "%%" .. escape(b) .. ".vim"
    if vim.uv.fs_stat(file) then
      return file
    end
  end
  local base = SESSION_DIR .. "/" .. name .. ".vim"
  if vim.uv.fs_stat(base) then
    return base
  end
end

---@return boolean there is a saved session for this folder
function M.exists()
  return M.file() ~= nil
end

--- Give restored terminals the config's Esc / Shift+Esc unless they already have their own (toggleterm, NvChad).
function M.attach_terminals()
  local function mapped_esc(buf)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if m.lhs == "<Esc>" then
        return true
      end
    end
    return false
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buftype == "terminal" and not mapped_esc(buf) then
      require("utils.terminal").attach_keys(buf, function()
        pcall(vim.api.nvim_win_close, 0, true)
      end)
    end
  end
end

--- Filetype detection is off while VimEnter runs (Neovim enables it after), so a session sourced there arrives with no
--- filetype: treesitter and LSP never start. Match the buffers that are still blank once the session is in place.
function M.detect_filetypes()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and vim.bo[buf].filetype == "" then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        local ft = vim.filetype.match { buf = buf, filename = name }
        if ft then
          vim.bo[buf].filetype = ft
        end
      end
    end
  end
end

--- Sources one session file (what `persistence.load` runs), firing its events and fixing restored terminals.
---@param file string
---@param opts { detect?: boolean }? `detect` = match filetypes: needed when sourcing inside VimEnter (detection is off then)
---@return boolean ok
function M.load_file(file, opts)
  local chat = package.loaded["agent.chat.window"]
  if chat then
    pcall(chat.hide)
  end
  vim.api.nvim_exec_autocmds("User", { pattern = "PersistenceLoadPre" })
  local ok, err = pcall(vim.cmd, "silent! source " .. vim.fn.fnameescape(file))
  vim.api.nvim_exec_autocmds("User", { pattern = "PersistenceLoadPost" })
  if opts and opts.detect then
    M.detect_filetypes()
  end
  M.attach_terminals()
  -- The plugin saves on exit and every minute; load it AFTER the session is on screen (it is not needed to source it).
  -- A session restored inside VimEnter would otherwise skip its BufReadPre lazy event forever.
  if package.loaded["lazy"] then
    vim.schedule(function()
      if not package.loaded["persistence"] then
        pcall(require("lazy").load, { plugins = { "persistence.nvim" } })
      end
    end)
  end
  if not ok then
    log.warn(("Session: %s"):format(tostring(err)))
  end
  return ok
end

function M.restore()
  local file = M.file()
  if not file then
    return log.warn "No saved session for this folder"
  end
  M.load_file(file)
end

--- Pick a session from any project (changes folder and restores it)
function M.pick()
  local p = persistence()
  if p then
    p.select()
  end
end

--- Restore the last saved session (from any project)
function M.last()
  local p = persistence()
  if not p then
    return log.warn "No saved sessions"
  end
  local file = p.last()
  if not file then
    return log.warn "No saved sessions"
  end
  M.load_file(file)
end

--- Should a start bring the project's session back? Pure over its inputs: no file on the command line (a folder is
--- fine), inside a project (not the home folder), a real UI, and the start screen still on screen (so no file was
--- opened first). `gui` is true inside the desktop app, whose gui/startup.lua already enters the project and restores it.
---@param ctx { enabled: boolean?, ui: boolean, gui: boolean?, args: integer, dir_arg: boolean?, stdin: boolean?, diff: boolean?, home: boolean?, start_screen: boolean, session: boolean }
---@return boolean
function M.should_restore(ctx)
  return ctx.enabled ~= false
    and ctx.ui == true
    and not ctx.gui
    and (ctx.args == 0 or ctx.dir_arg == true)
    and not ctx.stdin
    and not ctx.diff
    and not ctx.home
    and ctx.start_screen == true
    and ctx.session == true
end

--- Brings this folder's session back on a bare start (`leader` inside a project, or `leader <folder>`, no file
--- arguments). Never overwrites: with files on the command line the session is left alone. Returns whether it restored.
---@return boolean restored
function M.auto_restore()
  local args = vim.fn.argv()
  local dir_arg = #args == 1 and vim.fn.isdirectory(args[1]) == 1
  local before = vim.uv.cwd()
  if dir_arg then
    local dir = vim.fs.normalize(vim.fn.fnamemodify(args[1], ":p"))
    if vim.fs.normalize(vim.uv.cwd() or "") ~= dir then
      pcall(vim.cmd.cd, vim.fn.fnameescape(dir))
    end
  end
  local function back()
    if dir_arg and before and vim.fs.normalize(vim.uv.cwd() or "") ~= vim.fs.normalize(before) then
      pcall(vim.cmd.cd, vim.fn.fnameescape(before))
    end
  end
  local buf = vim.api.nvim_get_current_buf()
  local empty = vim.api.nvim_buf_get_name(buf) == ""
    and vim.api.nvim_buf_line_count(buf) == 1
    and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
  local cwd, home = vim.fs.normalize(vim.uv.cwd() or ""), vim.fs.normalize(vim.uv.os_homedir() or "")
  local ctx = {
    enabled = require("core.settings").session.auto_restore,
    ui = #vim.api.nvim_list_uis() > 0,
    gui = vim.g.leader_gui ~= nil,
    args = #args,
    dir_arg = dir_arg,
    stdin = vim.g.started_with_stdin ~= nil,
    diff = vim.o.diff,
    home = cwd == home,
    start_screen = dir_arg or vim.bo[buf].filetype == "nvdash" or empty,
    session = false,
  }
  if
    not (
      ctx.enabled
      and ctx.ui
      and not ctx.gui
      and (ctx.args == 0 or ctx.dir_arg)
      and not ctx.stdin
      and not ctx.diff
      and not ctx.home
      and ctx.start_screen
    )
  then
    back()
    return false
  end
  -- The file is found without loading persistence: a project with no session pays only two stat calls and two small reads.
  local file = M.file()
  ctx.session = file ~= nil
  if not M.should_restore(ctx) then
    back()
    return false
  end
  -- the start screen (and the empty first buffer) is not part of the session: leave only what the session restores.
  -- `%bwipeout!` only covers listed buffers and the dashboard is an unlisted scratch buffer, so it goes by name.
  pcall(vim.cmd, "silent! only")
  pcall(vim.cmd, "silent! %bwipeout!")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "nvdash" then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  return M.load_file(file, { detect = true })
end

--- Quit everything, asking first about unsaved changes (persistence saves the session on the way out).
function M.quit()
  vim.cmd "confirm qa"
end

function M.save()
  local p = persistence()
  if p then
    -- the chat's real splits would be saved as ghost file windows: hide it first
    local chat = package.loaded["agent.chat.window"]
    if chat then
      pcall(chat.hide)
    end
    p.save()
    log.info "Session saved"
  end
end

--- Stop saving the session on exit (only for this nvim run)
function M.stop()
  local p = persistence()
  if p then
    p.stop()
    log.info "This session won't be saved on exit"
  end
end

--- Close the non-file windows (nvim-tree, aerial, trouble, quickfix, help...) so they don't get saved in the session.
--- Terminals stay: `sessionoptions` includes `terminal`, and a terminal pane comes back as a fresh shell in its place.
function M.close_auxiliary()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    local floating = vim.api.nvim_win_get_config(win).relative ~= ""
    local buftype = vim.bo[buf].buftype
    if not floating and buftype ~= "" and buftype ~= "terminal" and #wins > 1 then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
end

return M
