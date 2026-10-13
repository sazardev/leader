-- ── Fuzzy picker (telescope) ─────────────────────────────────────────────────
-- Items: { label = "text", current = bool?, ... }. Marks the current one with ● and opens
-- the cursor on it. Without telescope it falls back to vim.ui.select.
local M = {}

---@param items table[]
---@param opts { title: string }
---@param on_choice fun(item: table)
function M.pick(items, opts, on_choice)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return vim.ui.select(items, {
      prompt = opts.title,
      format_item = function(item)
        return (item.current and "● " or "  ") .. item.label
      end,
    }, function(item)
      if item then
        on_choice(item)
      end
    end)
  end

  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"

  local index = 1
  for i, item in ipairs(items) do
    if item.current then
      index = i
    end
  end

  pickers
    .new(require("telescope.themes").get_dropdown { previewer = false, prompt_title = opts.title }, {
      finder = finders.new_table {
        results = items,
        entry_maker = function(item)
          return { value = item, ordinal = item.label, display = (item.current and "● " or "  ") .. item.label }
        end,
      },
      sorter = conf.generic_sorter {},
      default_selection_index = index,
      attach_mappings = function(bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(bufnr)
          if entry then
            on_choice(entry.value)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
