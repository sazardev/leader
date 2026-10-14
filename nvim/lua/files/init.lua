-- ── File operations (<leader>F, and a / r / d inside the tree) ───────────────
-- New file or folder, rename, move, duplicate, delete (to a trash you can undo), copy the path: one set of flat modals
-- for every place a file is touched. The pieces: paths.lua (pure), ops.lua (file system), buffers.lua (editor follows),
-- target.lua (what is selected), location.lua (the picture of the destination). This file only asks and chains.
local buffers = require "files.buffers"
local location = require "files.location"
local log = require "utils.log"
local modal = require "utils.modal"
local ops = require "files.ops"
local paths = require "files.paths"
local target = require "files.target"

local hl = modal.hl

local M = {}

---@return FilesTarget?
local function need_target()
  local t = target.resolve()
  if not t then
    log.warn "Files: no file here (open one, or put the cursor on one in the tree)"
  elseif t.root then
    log.warn "Files: that is the tree's root folder"
    return nil
  end
  return t
end

--- Opens a file; from the tree the tree closes first, like <CR> does
---@param path string
---@param in_tree boolean
local function open(path, in_tree)
  if in_tree and package.loaded["nvim-tree.api"] then
    require("nvim-tree.api").tree.close()
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

---@param count integer
---@param noun string
---@return string
local function plural(count, noun)
  return ("%d %s%s"):format(count, noun, count == 1 and "" or "s")
end

--- Creates what was typed under `base`
---@param kind "file"|"folder"
function M.new(kind)
  local t = target.resolve()
  local base = target.base(t)
  local lines = location.lines(base, "   <- new here")
  local hint = kind == "folder" and "e.g. docs; src/ui" or "e.g. main.go; docs/; src/ui/menu.go"
  vim.list_extend(lines, { "", { { hint, hl.muted } } })
  modal.input(lines, { title = kind == "folder" and "New folder" or "New file", confirm = "Create" }, function(input)
    local made, failed, first_file = {}, {}, nil
    for _, item in ipairs(paths.split(input)) do
      local valid, why = paths.valid(item.name)
      local path = paths.resolve(base, item.name)
      if valid then
        valid, why = ops.create(path, item.dir or kind == "folder")
      end
      if valid then
        made[#made + 1] = paths.display(path, vim.fn.getcwd())
        first_file = first_file or (not (item.dir or kind == "folder") and path or nil)
      else
        failed[#failed + 1] = ("%s (%s)"):format(item.name, why)
      end
    end
    buffers.refresh_tree()
    if first_file then
      open(first_file, t ~= nil and t.in_tree)
    end
    if #made > 0 then
      log.info("Created " .. table.concat(made, ", "))
    end
    if #failed > 0 then
      log.warn("Not created: " .. table.concat(failed, ", "))
    end
  end)
end

--- Moves `old` to `new` and makes the editor follow
---@param old string
---@param new string
---@return boolean
local function relocate(old, new)
  buffers.lsp_will_rename(old, new)
  local ok, why = ops.rename(old, new)
  if not ok then
    log.warn(("Files: %s (%s)"):format(paths.display(new, vim.fn.getcwd()), why))
    return false
  end
  buffers.renamed(old, new)
  buffers.lsp_did_rename(old, new)
  buffers.refresh_tree()
  log.info(("%s → %s"):format(paths.display(old, vim.fn.getcwd()), paths.display(new, vim.fn.getcwd())))
  return true
end

function M.rename()
  local t = need_target()
  if not t then
    return
  end
  local name = vim.fs.basename(t.path)
  local lines = {
    { { "Rename:" } },
    { { "  " }, { target.label(t), t.is_dir and hl.folder or hl.file } },
    "",
    { { "A / in the name moves it too", hl.muted } },
  }
  modal.input(
    lines,
    { title = t.is_dir and "Rename folder" or "Rename file", default = name, confirm = "Rename" },
    function(input)
      local valid, why = paths.valid(input)
      if input == name then
        return
      end
      if not valid then
        return log.warn("Files: " .. why)
      end
      relocate(t.path, paths.resolve(vim.fs.dirname(t.path), input))
    end
  )
end

--- Pick a folder (or make one) and move there
function M.move()
  local t = need_target()
  if not t then
    return
  end
  local root = vim.fn.getcwd()
  local name = vim.fs.basename(t.path)
  local here = vim.fs.dirname(t.path)
  local items = {}
  if here ~= root then
    items[#items + 1] = { label = "· project root", dir = root }
  end
  for _, rel in ipairs(ops.folders(root, t.is_dir and t.path or nil)) do
    if root .. "/" .. rel ~= here then
      items[#items + 1] = { label = rel .. "/", dir = root .. "/" .. rel }
    end
  end
  items[#items + 1] = { label = "+ new folder…", new = true }

  require("agent.ui.select").pick(items, { title = "Move " .. name .. " to" }, function(choice)
    if not choice.new then
      return relocate(t.path, choice.dir .. "/" .. name)
    end
    local lines = location.lines(root, "   <- relative to here")
    vim.list_extend(lines, { "", { { "Created if it does not exist", hl.muted } } })
    -- after the picker has finished closing: it leaves insert mode on its way out, which would undo the modal's own
    vim.schedule(function()
      modal.input(lines, { title = "Move " .. name .. " to", confirm = "Move" }, function(input)
        local valid, why = paths.valid(input)
        if not valid then
          return log.warn("Files: " .. why)
        end
        relocate(t.path, paths.resolve(root, input) .. "/" .. name)
      end)
    end)
  end)
end

function M.copy()
  local t = need_target()
  if not t then
    return
  end
  local dir = vim.fs.dirname(t.path)
  local suggestion = vim.fs.basename(paths.copy_name(t.path, ops.exists))
  local lines = {
    { { "Copy:" } },
    { { "  " }, { target.label(t), t.is_dir and hl.folder or hl.file } },
  }
  modal.input(
    lines,
    { title = t.is_dir and "Copy folder" or "Duplicate file", default = suggestion, confirm = "Duplicate" },
    function(input)
      local valid, why = paths.valid(input)
      if not valid then
        return log.warn("Files: " .. why)
      end
      local copy = paths.resolve(dir, input)
      local ok, err = ops.copy(t.path, copy)
      if not ok then
        return log.warn(("Files: %s (%s)"):format(paths.display(copy, vim.fn.getcwd()), err))
      end
      buffers.refresh_tree()
      log.info("Copied to " .. paths.display(copy, vim.fn.getcwd()))
      if not t.is_dir then
        open(copy, t.in_tree)
      end
    end
  )
end

function M.delete()
  local t = need_target()
  if not t then
    return
  end
  local lines = {
    { { t.is_dir and "Delete folder:" or "Delete file:" } },
    { { "  " }, { target.label(t), t.is_dir and hl.folder or hl.file } },
    "",
  }
  if t.is_dir then
    local files, dirs = ops.count(t.path)
    lines[#lines + 1] =
      { { "Contains: " }, { ("%s, %s"):format(plural(files, "file"), plural(dirs, "folder")), hl.file } }
  end
  local unsaved = buffers.unsaved_inside(t.path)
  if unsaved > 0 then
    lines[#lines + 1] = { { plural(unsaved, "open file") .. " with unsaved changes: they are lost.", hl.warn } }
  end
  lines[#lines + 1] = { { "Goes to the trash · <leader>Fu undoes it", hl.muted } }
  modal.confirm(lines, { title = "Delete", confirm = "Delete", danger = true }, function()
    local entry, why = ops.trash(t.path)
    if not entry then
      return log.warn(("Files: could not delete (%s)"):format(why))
    end
    buffers.removed(t.path)
    buffers.refresh_tree()
    log.info(("Deleted %s · <leader>Fu undoes it"):format(target.label(t)))
  end)
end

--- Brings back the last thing deleted
function M.undo()
  local path, why = ops.restore()
  if not path then
    return log.warn("Files: nothing restored (" .. why .. ")")
  end
  buffers.refresh_tree()
  log.info("Restored " .. paths.display(path, vim.fn.getcwd()))
end

---@param absolute boolean?
function M.copy_path(absolute)
  local t = target.resolve()
  if not t then
    return log.warn "Files: no file here"
  end
  local text = absolute and t.path or paths.display(t.path, vim.fn.getcwd())
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  log.info("Copied " .. text)
end

--- Shows the current file in the tree
function M.reveal()
  require("nvim-tree.api").tree.find_file { open = true, focus = true }
end

--- Find a file by name and open it
function M.open_file()
  require("telescope.builtin").find_files()
end

return M
