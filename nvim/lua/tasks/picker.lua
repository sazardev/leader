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
      default_selection_index = opts.select,
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
  show(tasks, { title = opts.title, results_title = "Enter run · C-a args · C-p dry run · C-r refresh" }, function(t)
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
  end, function(bufnr, map)
    local actions = require "telescope.actions"
    actions.select_default:replace(chosen(bufnr, opts.on_select))
    map({ "i", "n" }, "<C-a>", chosen(bufnr, opts.on_args))
    map({ "i", "n" }, "<C-p>", chosen(bufnr, opts.on_dry))
    map({ "i", "n" }, "<C-r>", function()
      actions.close(bufnr)
      vim.schedule(opts.on_refresh)
    end)
    return true
  end)
end

---@param items { label: string, desc: string?, path: string?, value: any, search: string? }[] `search`: more words the
--- filter matches without showing them (an id, a description)
---@param opts { title: string, preview: boolean?, width: integer?, select: integer?, on_cancel: fun()?, hint: string?, maps: { [1]: string, [2]: fun(value: any) }[]? }
--- `hint`: the results' title (the keys of the list). `maps`: more keys on the selected entry (`{ "<C-e>", fn }`).
--- `width`: of the label column (20; no `desc` on any item = the label alone). `select`: the row the cursor starts on.
--- `on_cancel`: Esc (and Ctrl-c) close the list and call it, e.g. to go back to the step before.
---@param on_select fun(value: any)
function M.choose(items, opts, on_select)
  local entry_display = require "telescope.pickers.entry_display"
  local with_desc = vim.iter(items):any(function(item)
    return item.desc ~= nil
  end)
  local displayer = entry_display.create {
    separator = "  ",
    items = with_desc and { { width = opts.width or 20 }, { remaining = true } } or { { remaining = true } },
  }
  show(
    items,
    { title = opts.title, results_title = opts.hint, preview = opts.preview, select = opts.select },
    function(item)
      return {
        value = item.value,
        path = item.path,
        lnum = item.lnum, -- the preview opens the file at that line (a requirement in SPEC.md)
        ordinal = item.label .. " " .. (item.desc or "") .. " " .. (item.search or ""),
        display = function()
          if not with_desc then
            return displayer { { item.label } }
          end
          return displayer { { item.label }, { item.desc or "", "Comment" } }
        end,
      }
    end,
    function(bufnr, map)
      require("telescope.actions").select_default:replace(chosen(bufnr, on_select))
      for _, m in ipairs(opts.maps or {}) do
        map({ "i", "n" }, m[1], chosen(bufnr, m[2]))
      end
      if opts.on_cancel then
        local function back()
          require("telescope.actions").close(bufnr)
          vim.schedule(opts.on_cancel)
        end
        map({ "i", "n" }, "<Esc>", back)
        map({ "i", "n" }, "<C-c>", back)
      end
      return true
    end
  )
end

return M
