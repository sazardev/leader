-- ── Go back after jumping (gd / grr / Ctrl+click) + file history ──────────────
-- 1) "Peek" stack: each jump records where it came from; <Esc> at the destination goes back (only
--    as long as you haven't edited there or moved to another buffer; several chained
--    jumps are undone one at a time).
-- 2) Session history: last visited files (<leader>H lists them).
local log = require "utils.log"

local M = {}

local MAX_STACK = 20
local MAX_HISTORY = 10

---@class nav.Origin
---@field buf integer
---@field pos integer[] {line, column}

---@type { origin: nav.Origin, buf: integer, tick: integer }[]
local stack = {}

--- Current point; call BEFORE jumping.
---@return nav.Origin
function M.origin()
  return { buf = vim.api.nvim_get_current_buf(), pos = vim.api.nvim_win_get_cursor(0) }
end

--- Record that a jump was made from `origin` to where the cursor is now.
---@param origin nav.Origin
function M.landed(origin)
  local buf = vim.api.nvim_get_current_buf()
  if buf == origin.buf and vim.api.nvim_win_get_cursor(0)[1] == origin.pos[1] then
    return -- didn't move
  end
  table.insert(stack, { origin = origin, buf = buf, tick = vim.b[buf].changedtick })
  if #stack > MAX_STACK then
    table.remove(stack, 1)
  end
end

--- Go back to the point before the last jump. false if not applicable (so <Esc>
--- does its usual thing).
---@return boolean
function M.back()
  local top = stack[#stack]
  if not top then
    return false
  end

  local buf = vim.api.nvim_get_current_buf()
  if top.buf ~= buf or vim.b[buf].changedtick ~= top.tick or not vim.api.nvim_buf_is_valid(top.origin.buf) then
    stack = {} -- you moved elsewhere or edited: it's no longer a "peek"
    return false
  end

  table.remove(stack)
  vim.api.nvim_set_current_buf(top.origin.buf)
  pcall(vim.api.nvim_win_set_cursor, 0, top.origin.pos)
  vim.cmd "normal! zz"
  return true
end

-- ── File history ─────────────────────────────────────────────────────────────

---@type { path: string, lnum: integer }[] most recent first
local history = {}

local function is_file(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return nil
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.fn.filereadable(path) == 0 then
    return nil
  end
  return path
end

--- Mark `buf` as the most recent file.
---@param buf integer
function M.track(buf)
  local path = is_file(buf)
  if not path then
    return
  end
  local lnum = 1
  if buf == vim.api.nvim_get_current_buf() then
    lnum = vim.api.nvim_win_get_cursor(0)[1]
  end
  for i, entry in ipairs(history) do
    if entry.path == path then
      lnum = lnum == 1 and entry.lnum or lnum
      table.remove(history, i)
      break
    end
  end
  table.insert(history, 1, { path = path, lnum = lnum })
  if #history > MAX_HISTORY + 1 then -- +1: the current file isn't shown
    table.remove(history)
  end
end

--- Save the line where `buf` was left (called when leaving it).
---@param buf integer
function M.save_position(buf)
  local path = is_file(buf)
  if not path or buf ~= vim.api.nvim_get_current_buf() then
    return
  end
  for _, entry in ipairs(history) do
    if entry.path == path then
      entry.lnum = vim.api.nvim_win_get_cursor(0)[1]
      return
    end
  end
end

--- List (with preview) of the last visited files, excluding the current one.
function M.history_picker()
  local current = vim.api.nvim_buf_get_name(0)
  local items = vim.tbl_filter(function(entry)
    return entry.path ~= current
  end, history)

  if #items == 0 then
    return log.info "You haven't visited any other files in this session yet"
  end

  local conf = require("telescope.config").values
  require("telescope.pickers")
    .new({
      prompt_title = "File history (most recent first)",
      sorting_strategy = "ascending",
      layout_config = { prompt_position = "top" },
    }, {
      finder = require("telescope.finders").new_table {
        results = items,
        entry_maker = function(entry)
          local rel = vim.fn.fnamemodify(entry.path, ":~:.")
          return {
            value = entry,
            display = ("%s:%d"):format(rel, entry.lnum),
            ordinal = rel,
            filename = entry.path,
            lnum = entry.lnum,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = conf.grep_previewer {},
    })
    :find()
end

return M
