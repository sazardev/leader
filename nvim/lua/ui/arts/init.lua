-- ── Dashboard ASCII art ──────────────────────────────────────────────────────
-- Catalog: one file per art in `lua/ui/arts/<name>.lua` returning the
-- list of lines. To add one: just create the file; the catalog is discovered
-- by scanning the folder (no list to maintain) every time it is needed.
-- IMPORTANT: every art must be made of DOTS (braille characters U+2800–U+28FF),
-- never ASCII/blocks/emoji, to keep the same style on the dashboard.
-- The choice is remembered across sessions (stdpath "state"/dashboard.json); the
-- initial value is `settings.dashboard.art`.
local log = require "utils.log"
local settings = require "core.settings"

local M = {}

--- Available arts: one `<name>.lua` per art in this folder (except init).
---@return string[] sorted names
function M.names()
  local names, seen = {}, {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/ui/arts/*.lua", true)) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    if name ~= "init" and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

local function state_path()
  return vim.fn.stdpath "state" .. "/dashboard.json"
end

---@return string?
local function read_saved()
  local f = io.open(state_path(), "r")
  if not f then
    return nil
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data.art or nil
end

---@param name string
local function write_saved(name)
  vim.fn.mkdir(vim.fs.dirname(state_path()), "p")
  local f = io.open(state_path(), "w")
  if f then
    f:write(vim.json.encode { art = name })
    f:close()
  end
end

---@param name string
---@return boolean
local function valid(name)
  return vim.tbl_contains(M.names(), name)
end

---@return string chosen name
function M.current()
  local saved = read_saved()
  if saved and valid(saved) then
    return saved
  end
  return valid(settings.dashboard.art) and settings.dashboard.art or M.names()[1]
end

--- Pads the lines to the same width: nvdash centers each line separately and
--- an art with uneven lines would look crooked.
---@param lines string[]
---@return string[]
local function pad(lines)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  return vim.tbl_map(function(l)
    return l .. string.rep(" ", width - vim.fn.strdisplaywidth(l))
  end, lines)
end

---@param name string
---@return string[]
function M.load(name)
  -- no cache: this way an edited art shows up when reopening the picker without restarting nvim
  package.loaded["ui.arts." .. name] = nil
  local ok, lines = pcall(require, "ui.arts." .. name)
  if not ok or type(lines) ~= "table" then
    log.warn(("Art '%s' could not be loaded"):format(name))
    return {}
  end
  return pad(lines)
end

---@return string[] lines of the active art
function M.lines()
  return M.load(M.current())
end

--- Redraws the dashboard if visible. nvdash replaces `header` with its
--- result on the first draw, so the function must be put back.
local function redraw()
  local buf = vim.g.nvdash_buf
  local win = buf and vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) or -1
  if win == -1 then
    return
  end
  require("nvconfig").nvdash.header = M.lines
  vim.api.nvim_buf_clear_namespace(buf, vim.api.nvim_create_namespace "nvdash", 0, -1)
  local modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  require("nvchad.nvdash").open(buf, win, "redraw")
  vim.bo[buf].modifiable = modifiable
end

---@param name string
function M.set(name)
  if not valid(name) then
    return log.warn(("Unknown art: %s"):format(name))
  end
  write_saved(name)
  redraw()
  log.info("Dashboard art: " .. name)
end

--- Picker with preview (Telescope); falls back to vim.ui.select without Telescope.
function M.pick()
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return vim.ui.select(M.names(), { prompt = "Dashboard art" }, function(choice)
      if choice then
        M.set(choice)
      end
    end)
  end

  local finders = require "telescope.finders"
  local previewers = require "telescope.previewers"
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local conf = require("telescope.config").values

  local names = M.names()
  pickers
    .new({}, {
      prompt_title = "Dashboard art",
      finder = finders.new_table { results = names },
      sorter = conf.generic_sorter {},
      default_selection_index = (vim.fn.index(names, M.current()) + 1),
      layout_strategy = "horizontal",
      layout_config = { width = 0.7, height = 0.6, preview_width = 0.6 },
      previewer = previewers.new_buffer_previewer {
        title = "Preview",
        define_preview = function(self, entry)
          local lines = M.load(entry[1])
          local buf = self.state.bufnr
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          for i = 1, #lines do
            vim.api.nvim_buf_add_highlight(buf, -1, "NvDashAscii", i - 1, 0, -1)
          end
        end,
      },
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            M.set(entry[1])
          end
        end)
        return true
      end,
    })
    :find()
end

return M
