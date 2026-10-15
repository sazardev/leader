-- ── Pickers ──────────────────────────────────────────────────────────────────
-- `open`: the Makefile's tasks (Enter runs, <C-a> asks for arguments, <C-p> prints what it would do, <C-r> reads the
-- Makefile again). `choose`: a plain list, with a file preview when the items have a `path` (the presets).
local M = {}

---@param items table[]
---@param opts table
---@param entry_maker fun(item: any): table
---@param attach fun(bufnr: integer, map: function): boolean
local function show(items, opts, entry_maker, attach)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  pickers
    .new({}, {
      prompt_title = opts.title,
      results_title = opts.results_title,
      finder = finders.new_table { results = items, entry_maker = entry_maker },
      sorter = conf.generic_sorter {},
      previewer = opts.preview and conf.file_previewer {} or nil,
      attach_mappings = attach,
    })
    :find()
end

--- Runs `fn(value)` on the selected entry once the picker has finished closing (the callbacks open modals or a terminal)
---@param bufnr integer
---@param fn fun(value: any)
local function chosen(bufnr, fn)
  return function()
    local entry = require("telescope.actions.state").get_selected_entry()
    require("telescope.actions").close(bufnr)
    if entry then
      vim.schedule(function()
        fn(entry.value)
      end)
    end
  end
end

---@param tasks Task[]
---@param opts { title: string, on_select: fun(t: Task), on_args: fun(t: Task), on_dry: fun(t: Task), on_refresh: fun() }
function M.open(tasks, opts)
  local entry_display = require "telescope.pickers.entry_display"
  local displayer = entry_display.create {
    separator = "  ",
    items = { { width = 1 }, { width = 28 }, { remaining = true } },
  }
  show(
    tasks,
    { title = opts.title, results_title = "Enter run · C-a args · C-p dry run · C-r refresh" },
    function(t)
      return {
        value = t,
        ordinal = t.name .. " " .. (t.desc or ""),
        display = function()
          return displayer {
            { t.default and "●" or " ", "FlatMark" },
            { t.name },
            { t.desc or "", "Comment" },
          }
        end,
      }
    end,
    function(bufnr, map)
      local actions = require "telescope.actions"
      actions.select_default:replace(chosen(bufnr, opts.on_select))
      map({ "i", "n" }, "<C-a>", chosen(bufnr, opts.on_args))
      map({ "i", "n" }, "<C-p>", chosen(bufnr, opts.on_dry))
      map({ "i", "n" }, "<C-r>", function()
        actions.close(bufnr)
        vim.schedule(opts.on_refresh)
      end)
      return true
    end
  )
end

---@param items { label: string, desc: string?, path: string?, value: any }[]
---@param opts { title: string, preview: boolean? }
---@param on_select fun(value: any)
function M.choose(items, opts, on_select)
  local entry_display = require "telescope.pickers.entry_display"
  local displayer = entry_display.create { separator = "  ", items = { { width = 20 }, { remaining = true } } }
  show(items, { title = opts.title, preview = opts.preview }, function(item)
    return {
      value = item.value,
      path = item.path,
      ordinal = item.label .. " " .. (item.desc or ""),
      display = function()
        return displayer { { item.label }, { item.desc or "", "Comment" } }
      end,
    }
  end, function(bufnr)
    require("telescope.actions").select_default:replace(chosen(bufnr, on_select))
    return true
  end)
end

return M
