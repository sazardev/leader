-- ── Desktop app: projects ────────────────────────────────────────────────────
-- A project is a folder Neovim works in. Every folder you work in is remembered
-- (stdpath("state")/leader-projects.json, newest first), so the bar's project
-- menu can bring you back. Switching saves the current session (persistence.nvim,
-- one per folder), changes folder and restores that folder's session, or shows
-- the start screen when it has none. Unsaved files are never dropped: you are
-- asked to save them first. "Open folder…" finds the git projects under your home
-- (fd, else find) in Telescope; "Open path…" takes a folder you type.
local M = {}

local FILE = vim.fn.stdpath "state" .. "/leader-projects.json"
local MAX = 30

---@return { dir: string, at: integer }[]
function M.list()
  local f = io.open(FILE)
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  if not (ok and type(data) == "table") then
    return {}
  end
  return vim.tbl_filter(function(p)
    return type(p) == "table" and type(p.dir) == "string" and vim.fn.isdirectory(p.dir) == 1
  end, data)
end

---@param list { dir: string, at: integer }[]
local function write(list)
  vim.fn.mkdir(vim.fs.dirname(FILE), "p")
  local f = io.open(FILE, "w")
  if f then
    f:write(vim.json.encode(list))
    f:close()
  end
end

---@param dir string
---@return string
function M.normalize(dir)
  local full = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(dir), ":p"))
  return (#full > 1 and full:gsub("/+$", "")) or full
end

--- Remembers a folder as the newest project (the home folder and "/" are not projects).
---@param dir string
function M.remember(dir)
  dir = M.normalize(dir)
  if dir == M.normalize "~" or dir == "/" or vim.fn.isdirectory(dir) == 0 then
    return
  end
  local list = vim.tbl_filter(function(p)
    return p.dir ~= dir
  end, M.list())
  table.insert(list, 1, { dir = dir, at = os.time() })
  while #list > MAX do
    table.remove(list)
  end
  write(list)
end

---@param dir string
function M.forget(dir)
  dir = M.normalize(dir)
  write(vim.tbl_filter(function(p)
    return p.dir ~= dir
  end, M.list()))
end

---@return integer[] listed buffers with unsaved changes
local function modified()
  return vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.bo[b].modified and vim.bo[b].buftype == ""
  end, vim.api.nvim_list_bufs())
end

local function has_files()
  return vim.iter(vim.api.nvim_list_bufs()):any(function(b)
    return vim.bo[b].buflisted and vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= ""
  end)
end

--- Switches to another project: session saved, folder changed, its session (or the start screen) restored.
---@param dir string
function M.switch(dir)
  dir = M.normalize(dir)
  if vim.fn.isdirectory(dir) == 0 then
    return vim.notify("Leader: " .. dir .. " is not a folder", vim.log.levels.WARN)
  end
  if dir == M.normalize(vim.uv.cwd() or "") then
    return
  end
  local function go()
    local ok, persistence = pcall(require, "persistence")
    if ok and has_files() then
      require("utils.session").close_auxiliary()
      pcall(persistence.save)
    end
    pcall(vim.cmd, "silent! only")
    pcall(vim.cmd, "silent! %bwipeout!")
    vim.cmd.cd(vim.fn.fnameescape(dir))
    M.remember(dir)
    if ok and require("utils.session").exists() then
      pcall(persistence.load)
    else
      require("ui.start").open()
    end
  end
  local unsaved = modified()
  if #unsaved == 0 then
    return go()
  end
  require("utils.modal").confirm({
    ("%d file%s with unsaved changes."):format(#unsaved, #unsaved == 1 and "" or "s"),
    "Save them and open " .. vim.fn.fnamemodify(dir, ":t") .. "?",
  }, { title = "Switch project", confirm = "Save and switch" }, function()
    vim.cmd "silent wall"
    go()
  end)
end

--- Telescope over the git projects under the home folder (the remembered ones are in the projects menu).
function M.find()
  local ok = pcall(require, "telescope")
  if not ok then
    return M.ask()
  end
  local pickers, finders, conf =
    require "telescope.pickers", require "telescope.finders", require("telescope.config").values
  local actions, action_state = require "telescope.actions", require "telescope.actions.state"
  local home = vim.uv.os_homedir() or "~"
  local skip = { ".cache", ".local", ".cargo", ".rustup", ".npm", "node_modules", "go", ".git/modules", "snap" }
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
  local seen = {}
  local function entry(dir)
    dir = M.normalize(dir)
    if seen[dir] then
      return nil
    end
    seen[dir] = true
    local shown = vim.fn.fnamemodify(dir, ":~")
    return { value = dir, display = ("%-28s %s"):format(vim.fn.fnamemodify(dir, ":t"), shown), ordinal = shown }
  end
  pickers
    .new({}, {
      prompt_title = "Open Folder",
      finder = finders.new_oneshot_job(cmd, {
        entry_maker = function(line)
          return entry(vim.fs.dirname(line))
        end,
      }),
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt)
        actions.select_default:replace(function()
          local e = action_state.get_selected_entry()
          actions.close(prompt)
          if e then
            M.switch(e.value)
          end
        end)
        return true
      end,
    })
    :find()
end

--- A folder typed by hand (with ~ and relative paths).
function M.ask()
  local parent = vim.fn.fnamemodify(vim.uv.cwd() or "~", ":h")
  require("utils.modal").input({ "Folder to open" }, {
    title = "Open path",
    default = vim.fn.fnamemodify(parent, ":~") .. "/",
    confirm = "Open",
  }, function(text)
    if text and text ~= "" then
      M.switch(text)
    end
  end)
end

function M.setup(group)
  vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
    group = group,
    callback = function()
      M.remember(vim.uv.cwd() or "")
    end,
  })
end

return M
