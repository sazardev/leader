-- ── Recent files of THIS project (<leader>fo, the start screen, the app's ↺) ─
-- Not Neovim's global oldfiles: only files inside the project you are in (the git root above the folder, else the
-- folder), newest first, the ones open now on top, each shown relative to the project. <C-a> widens it to every
-- project for the one time you need a file from elsewhere (paths then shown from ~), <C-x> forgets an entry.
-- What is recorded and how lists are built: recent/store.lua, recent/list.lua (pure, tested in test-recent.sh).
local list = require "recent.list"
local store = require "recent.store"

local M = {}

--- The project the editor is in: the git root above the working folder, else the folder itself.
---@return string
function M.project()
  local cwd = vim.uv.cwd() or ""
  local root = vim.fs.root(cwd, ".git")
  return (root and root ~= vim.uv.os_homedir()) and root or cwd
end

---@param buf integer
---@return string? path of a real file worth remembering
local function file_of(buf)
  if vim.bo[buf].buftype ~= "" or not vim.bo[buf].buflisted then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.fn.filereadable(name) == 0 or not list.recent_worthy(name) then
    return nil
  end
  return name
end

---@return string[]
local function open_files()
  local out = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = file_of(buf) -- listed buffers count loaded or not (the second file given on the command line)
    if name then
      out[#out + 1] = name
    end
  end
  return out
end

--- The entries to show.
---@param all boolean? every project instead of this one
---@return RecentEntry[]
function M.entries(all)
  local root = not all and M.project() or nil
  local max = (require("core.settings").recent or {}).max or 200
  return list.build(root, {
    store = root and store.get(root) or store.all(),
    oldfiles = vim.v.oldfiles or {},
    open = vim.tbl_filter(function(p)
      return not root or list.inside(p, root)
    end, open_files()),
    exists = function(p)
      return vim.uv.fs_stat(p) ~= nil
    end,
    now = os.time(),
    max = max,
  })
end

function M.setup()
  local group = vim.api.nvim_create_augroup("RecentFiles", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      local name = file_of(ev.buf)
      if name then
        store.record(store.project_of(name, vim.uv.cwd() or ""), name)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "VimLeavePre", "FocusLost", "DirChanged" }, {
    group = group,
    callback = store.save,
  })
end

---@param seconds integer
---@return string
local function age(seconds)
  local d = os.time() - seconds
  if d < 60 then
    return "now"
  elseif d < 3600 then
    return math.floor(d / 60) .. "m"
  elseif d < 86400 then
    return math.floor(d / 3600) .. "h"
  end
  return math.floor(d / 86400) .. "d"
end

---@param all boolean? start in every project
function M.open(all)
  local ok = pcall(require, "telescope")
  if not ok then
    return vim.notify("Recent files need Telescope", vim.log.levels.WARN)
  end
  local pickers, finders = require "telescope.pickers", require "telescope.finders"
  local conf = require("telescope.config").values
  local actions, state = require "telescope.actions", require "telescope.actions.state"
  local project = M.project()
  local name = vim.fn.fnamemodify(project, ":t")
  local scope_all = all == true

  local function finder()
    local displayer = require("telescope.pickers.entry_display").create {
      separator = "  ",
      items = { { width = 4 }, { remaining = true } },
    }
    return finders.new_table {
      results = M.entries(scope_all),
      entry_maker = function(e)
        local shown = scope_all and vim.fn.fnamemodify(e.path, ":~") or e.path:sub(#project + 2)
        return {
          value = e,
          path = e.path,
          ordinal = shown,
          display = function()
            return displayer { { e.at and age(e.at) or "", "Comment" }, shown }
          end,
        }
      end,
    }
  end

  local function titles(picker)
    picker.prompt_border:change_title(scope_all and "Recent files · every project" or ("Recent files · " .. name))
  end

  local first = finder()
  if #first.results == 0 and not scope_all then
    vim.notify(
      ("No recent files in %s yet. <leader>fo again with C-a for every project."):format(name),
      vim.log.levels.INFO
    )
  end
  pickers
    .new({}, {
      prompt_title = scope_all and "Recent files · every project" or ("Recent files · " .. name),
      results_title = "Enter open · C-a every project · C-x forget",
      finder = first,
      sorter = conf.file_sorter {},
      previewer = conf.file_previewer {},
      attach_mappings = function(bufnr, map)
        map({ "i", "n" }, "<C-a>", function()
          scope_all = not scope_all
          local picker = state.get_current_picker(bufnr)
          picker:refresh(finder(), { reset_prompt = false })
          pcall(titles, picker)
        end)
        map({ "i", "n" }, "<C-x>", function()
          local entry = state.get_selected_entry()
          if entry then
            store.forget(store.project_of(entry.value.path, vim.uv.cwd() or ""), entry.value.path)
            state.get_current_picker(bufnr):refresh(finder(), { reset_prompt = false })
          end
        end)
        actions.select_default:enhance {}
        return true
      end,
    })
    :find()
end

return M
