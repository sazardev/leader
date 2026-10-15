-- ── Code search (<leader>fs): "where is X handled?" with 0 tokens ─────────────
-- Type a question or a few words; the picker ranks the project's functions and types by what their names, doc comments,
-- signatures and paths say (`codesearch/rank.lua`, pure) over a treesitter index (`codesearch/index.lua`). No model, no
-- vectors, no network. The agent can read the same index to answer with only the best hits as context.
local M = {}

local settings = require("core.settings").search

---@param root string
---@param list CodeSymbol[]
local function picker(root, list)
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local sorters = require "telescope.sorters"
  local entry_display = require "telescope.pickers.entry_display"
  local rank = require "codesearch.rank"

  local displayer = entry_display.create {
    separator = "  ",
    items = { { width = 1 }, { width = 34 }, { width = 8 }, { remaining = true } },
  }

  pickers
    .new({}, {
      prompt_title = "Code search (" .. #list .. " symbols)",
      finder = finders.new_dynamic {
        fn = function(prompt)
          return rank.search(list, prompt or "", settings.results)
        end,
        entry_maker = function(sym)
          local abs = root .. "/" .. sym.path
          return {
            value = sym,
            ordinal = sym.name .. " " .. sym.path,
            filename = abs,
            lnum = sym.line,
            col = 1,
            display = function()
              return displayer {
                { "" },
                { sym.name },
                { sym.kind == "type" and "type" or "func", "Comment" },
                { ("%s:%d"):format(sym.path, sym.line), "Comment" },
              }
            end,
          }
        end,
      },
      -- the ranking is already done: telescope must not reorder or filter again
      sorter = sorters.empty(),
      previewer = conf.grep_previewer {},
    })
    :find()
end

--- Opens the picker (builds or refreshes the index first)
---@param root string?
function M.open(root)
  root = root or vim.fs.root(0, { ".git" }) or vim.fn.getcwd()
  local log = require "utils.log"
  if vim.fn.executable "rg" ~= 1 then
    return log.warn "Code search: ripgrep (rg) is required"
  end
  local notified = false
  require("codesearch.index").build(root, function(list, stats)
    if #list == 0 then
      return log.warn "Code search: no functions or types found (is a treesitter parser installed for this project?)"
    end
    if stats.skipped > 0 then
      log.info(
        ("Code search: indexed the first %d files (%d more skipped: settings.search.max_files)"):format(
          stats.files,
          stats.skipped
        )
      )
    end
    picker(root, list)
  end, function(done, total)
    if not notified and total > 400 and done < total then
      notified = true
      log.info(("Code search: indexing %d files…"):format(total))
    end
  end)
end

return M
