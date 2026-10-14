-- ── Run history (telescope) ──────────────────────────────────────────────────
-- One row per action: when, outcome, action, model, target, tokens and cost. The preview
-- shows EVERYTHING: your instruction, the code sent, the response, the system prompt and the exact message sent.
--   <CR> full detail (BS comes back) · <C-f> filter (agent, provider, model, action, outcome, project) · <C-x> clear
--   filters · <C-y> copies EVERYTHING · <C-p> copies only the prompt · <C-s> spend report (BS comes back)
-- Coming back restores the filters, what was typed and the selected run.
local clipboard = require "agent.ui.clipboard"
local detail = require "agent.runs.detail"
local filter = require "agent.runs.filter"
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

---@class AgentHistoryState
---@field filter? table<string, string>
---@field prompt? string what was typed in the picker
---@field select? number timestamp of the selected run

---@param back? AgentHistoryState reopen the history like this on BS
function M.report(back)
  panel.open(report.build(store.read()), "Agent usage", back and {
    on_back = function()
      M.open(back)
    end,
  } or nil)
end

--- Two short lists: which dimension, then which value (with runs and cost each); the history reopens filtered.
--- Esc in either goes back to the history as it was.
---@param state AgentHistoryState
local function choose_filter(state)
  local select = require "agent.ui.select"
  local all = filter.apply(store.read(), state.filter)
  local back = function()
    M.open(state)
  end
  local dims = {}
  for _, d in ipairs(filter.DIMS) do
    local values = filter.values(all, d.key)
    local preview = {}
    for i = 1, math.min(3, #values) do
      preview[#preview + 1] = values[i].value
    end
    dims[#dims + 1] = {
      label = ("%-9s %s%s"):format(d.label, table.concat(preview, ", "), #values > 3 and ", …" or ""),
      key = d.key,
      current = state.filter and state.filter[d.key] ~= nil,
    }
  end
  select.pick(dims, { title = "Filter history by", on_cancel = back }, function(dim)
    local items = {}
    for _, v in ipairs(filter.values(all, dim.key)) do
      items[#items + 1] = {
        label = ("%-28s %3d run%s  %s"):format(v.value, v.count, v.count == 1 and " " or "s", fmt.money(v.cost)),
        value = v.value,
        current = state.filter and state.filter[dim.key] == v.value,
      }
    end
    select.pick(items, { title = filter.dim(dim.key).label, on_cancel = back }, function(item)
      local f = vim.deepcopy(state.filter or {})
      f[dim.key] = item.value
      M.open { filter = f }
    end)
  end)
end

---@param state? AgentHistoryState
function M.open(state)
  state = state or {}
  local everything = store.read()
  if #everything == 0 then
    return log.info "Agent: no runs recorded yet"
  end
  local runs = filter.apply(everything, state.filter)
  if #runs == 0 then
    log.info("Agent: no runs match " .. filter.label(state.filter) .. "; showing all")
    state = { prompt = state.prompt }
    runs = everything
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

  local selection
  for i, run in ipairs(runs) do
    if state.select and run.ts == state.select then
      selection = i
    end
  end
  local active = filter.label(state.filter)

  pickers
    .new({}, {
      prompt_title = ("Agent history · %s%s"):format(active ~= "" and (active .. " · ") or "", report.headline(runs)),
      results_title = "<C-f> filter · <C-x> clear · <C-y> copy all · <C-p> copy prompt · <C-s> usage",
      default_text = state.prompt,
      default_selection_index = selection,
      finder = finders.new_table {
        results = runs,
        entry_maker = function(run)
          local u = run.usage or {}
          return {
            value = run,
            ordinal = table.concat(
              { run.action, fmt.model(run), fmt.target(run), run.outcome or "", run.input or "" },
              " "
            ),
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
          local buf, win = self.state.bufnr, self.state.winid
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, detail.build(entry.value))
          vim.bo[buf].filetype = "markdown"
          vim.diagnostic.enable(false, { bufnr = buf })
          vim.wo[win].wrap = true
          vim.wo[win].linebreak = true
          M.render_markdown(buf, win)
        end,
      },
      attach_mappings = function(bufnr, map)
        --- how the history is right now: to come back to it exactly
        local function here()
          local entry = action_state.get_selected_entry()
          return {
            filter = state.filter,
            prompt = action_state.get_current_line(),
            select = entry and entry.value.ts or nil,
          }
        end
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          local back = here()
          actions.close(bufnr)
          if entry then
            panel.open(detail.build(entry.value), "Agent run", {
              on_back = function()
                M.open(back)
              end,
            })
          end
        end)
        map({ "i", "n" }, "<C-s>", function()
          local back = here()
          actions.close(bufnr)
          M.report(back)
        end)
        map({ "i", "n" }, "<C-f>", function()
          local back = here()
          actions.close(bufnr)
          vim.schedule(function()
            choose_filter(back)
          end)
        end)
        map({ "i", "n" }, "<C-x>", function()
          if not (state.filter and next(state.filter)) then
            return
          end
          local back = here()
          actions.close(bufnr)
          vim.schedule(function()
            M.open { prompt = back.prompt, select = back.select }
          end)
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

--- Renders a run's markdown in a preview: highlighting (code fences in their language, through treesitter
--- injections) and the markdown renderer (scratch buffers render in every mode: plugins/ui/render-markdown.lua)
---@param buf integer
---@param win integer
function M.render_markdown(buf, win)
  pcall(vim.treesitter.start, buf, "markdown")
  -- telescope puts the buffer in its window a moment after `define_preview`, and the renderer only draws a buffer its
  -- window already shows: wait for that (a few short tries; a newer preview may have taken the window meanwhile)
  local tries = 0
  local function render()
    if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
      return
    end
    if vim.api.nvim_win_get_buf(win) ~= buf then
      tries = tries + 1
      if tries < 20 then
        vim.defer_fn(render, 15)
      end
      return
    end
    pcall(function()
      require("render-markdown.api").render { buf = buf, win = win }
    end)
  end
  vim.schedule(render)
  -- once more when the picker has settled: right after it opens, its first redraws can wipe the first rendering
  vim.defer_fn(render, 150)
end

return M
