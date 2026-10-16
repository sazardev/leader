-- ── Yank history picker (<leader>uy) ─────────────────────────────────────────
-- Newest first, the whole text in the preview (highlighted as the file it came from). Enter pastes it after the
-- cursor and makes it the clipboard again (the next `p` repeats it), <C-x> forgets the entry.
local yanks = require "history.yanks"

local M = {}

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

function M.open()
  local items = yanks.list()
  if #items == 0 then
    return vim.notify("Nothing yanked yet", vim.log.levels.INFO)
  end
  local win = vim.api.nvim_get_current_win()
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local previewers = require "telescope.previewers"
  local actions = require "telescope.actions"
  local state = require "telescope.actions.state"
  local conf = require("telescope.config").values
  local displayer = require("telescope.pickers.entry_display").create {
    separator = "  ",
    items = { { width = 3 }, { remaining = true } },
  }

  local function finder()
    return finders.new_table {
      results = yanks.list(),
      entry_maker = function(e)
        return {
          value = e,
          ordinal = table.concat(e.lines, " "),
          display = function()
            return displayer { { age(e.time), "Comment" }, { yanks.label(e) } }
          end,
        }
      end,
    }
  end

  pickers
    .new({}, {
      prompt_title = "Yank history",
      results_title = "Enter paste · C-x forget",
      finder = finder(),
      sorter = conf.generic_sorter {},
      previewer = previewers.new_buffer_previewer {
        title = "Text",
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, entry.value.lines)
          if entry.value.ft and entry.value.ft ~= "" then
            require("telescope.previewers.utils").highlighter(self.state.bufnr, entry.value.ft)
          end
        end,
      },
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(bufnr)
          if not entry then
            return
          end
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_set_current_win(win)
            end
            yanks.select(entry.value)
            yanks.put(entry.value, "p", 1)
          end)
        end)
        map({ "i", "n" }, "<C-x>", function()
          local entry = state.get_selected_entry()
          local i = entry and yanks.find(yanks.list(), entry.value.lines)
          if i then
            yanks.remove(i)
            state.get_current_picker(bufnr):refresh(finder(), { reset_prompt = false })
          end
        end)
        return true
      end,
    })
    :find()
end

return M
