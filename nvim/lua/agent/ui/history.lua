-- ── Run history (telescope) ──────────────────────────────────────────────────
-- One row per action: when, outcome, action, model, target, tokens and cost. The preview
-- shows EVERYTHING: your instruction, the response, the system prompt and the exact message sent.
--   <CR> full detail · <C-y> copies EVERYTHING · <C-p> copies only the prompt · <C-s> spend report
local clipboard = require "agent.ui.clipboard"
local detail = require "agent.runs.detail"
local fmt = require "agent.runs.format"
local log = require "utils.log"
local panel = require "agent.ui.panel"
local report = require "agent.runs.report"
local store = require "agent.runs.store"

local M = {}

local OUTCOME_HL = {
  accepted = "DiagnosticOk",
  rejected = "DiagnosticWarn",
  discarded = "Comment",
  unchanged = "Comment",
  pending = "Comment",
  findings = "DiagnosticInfo",
  shown = "Comment",
  error = "DiagnosticError",
  cancelled = "DiagnosticWarn",
}

function M.report()
  panel.open(report.build(store.read()), "Agent usage")
end

function M.open()
  local runs = store.read()
  if #runs == 0 then
    return log.info "Agent: no runs recorded yet"
  end
  local ok = pcall(require, "telescope.pickers")
  if not ok then
    return M.report()
  end

  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local conf = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local previewers = require "telescope.previewers"
  local entry_display = require "telescope.pickers.entry_display"

  local displayer = entry_display.create {
    separator = " ",
    items = { { width = 11 }, { width = 1 }, { width = 9 }, { width = 7 }, { width = 8 }, { remaining = true } },
  }

  pickers
    .new({}, {
      prompt_title = ("Agent history · %s"):format(report.headline(runs)),
      results_title = "<C-y> copy all · <C-p> copy prompt · <C-s> usage report",
      finder = finders.new_table {
        results = runs,
        entry_maker = function(run)
          local u = run.usage or {}
          return {
            value = run,
            ordinal = table.concat({ run.action, fmt.model(run), fmt.target(run), run.outcome, run.input or "" }, " "),
            display = function()
              return displayer {
                { os.date("%m-%d %H:%M", run.ts), "Comment" },
                { fmt.icon(run), OUTCOME_HL[run.outcome] },
                run.action,
                { (run.model or "default"), "Comment" },
                fmt.money(u.cost),
                fmt.target(run),
              }
            end,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      -- the list needs width (date, cost, target): the preview gets half
      layout_config = { width = 0.96, height = 0.88, horizontal = { preview_width = 0.5, preview_cutoff = 0 } },
      previewer = previewers.new_buffer_previewer {
        title = "Run",
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, detail.build(entry.value))
          vim.bo[self.state.bufnr].filetype = "markdown"
          vim.diagnostic.enable(false, { bufnr = self.state.bufnr })
          vim.wo[self.state.winid].wrap = true
        end,
      },
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(bufnr)
          if entry then
            panel.open(detail.build(entry.value), "Agent run")
          end
        end)
        map({ "i", "n" }, "<C-s>", function()
          actions.close(bufnr)
          M.report()
        end)
        map({ "i", "n" }, "<C-y>", function()
          local entry = action_state.get_selected_entry()
          if entry then
            clipboard.copy(detail.text(entry.value), "the whole run")
          end
        end)
        map({ "i", "n" }, "<C-p>", function()
          local entry = action_state.get_selected_entry()
          local run = entry and entry.value
          if not (run and run.system and run.prompt) then
            return log.warn "Agent: this run has no stored prompt (history.store_text is off)"
          end
          clipboard.copy(run.system .. "\n\n" .. run.prompt, "the prompt")
        end)
        return true
      end,
    })
    :find()
end

return M
