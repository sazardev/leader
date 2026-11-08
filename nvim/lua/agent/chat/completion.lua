-- ── Input triggers: orchestration ───────────────────────────────────────────
-- Reads the input, asks trigger.lua what is being typed, fills the selector
-- (popup.lua) with suggest.lua's rows and accepts the choice: `/command` runs
-- at once, a mention is inserted. All the decisions are pure and tested; this
-- file only touches buffers/timers.
local popup = require "agent.chat.popup"
local suggest = require "agent.chat.suggest"
local trigger = require "agent.chat.trigger"

local M = {}

---@return boolean
function M.is_visible()
  return popup.is_visible()
end

function M.hide()
  popup.hide()
end

--- Detects the trigger under the cursor (pure, exposed for tests).
---@param line string
---@param col integer
---@return string? kind, string? query, integer? start_col, integer? end_col
function M.detect(line, col)
  return trigger.detect(line, col)
end

---@param kind string
---@param query string
---@return table[]
function M.candidates(kind, query)
  return suggest.all(kind, query)
end

--- Show/update the selector for the current cursor. `input_win` may be stale
--- (the panel reopens its windows): the one showing the buffer is resolved.
---@param input_buf integer
---@param input_win integer?
function M.sync(input_buf, input_win)
  if not (input_buf and vim.api.nvim_buf_is_valid(input_buf)) then
    return M.hide()
  end
  local win = input_win
  if not (win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == input_buf) then
    win = vim.fn.bufwinid(input_buf)
  end
  if win == -1 or not vim.api.nvim_win_is_valid(win) then
    return M.hide()
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(input_buf, row - 1, row, false)[1] or ""
  local kind, query, start_col = trigger.detect(line, col)
  if not kind then
    return M.hide()
  end
  local items = suggest.all(kind, query)
  if #items == 0 then
    return M.hide()
  end
  popup.show(kind, items, { win = win, row = row, col = start_col })
end

---@param delta integer
function M.move(delta)
  popup.move(delta)
end

--- Accepts the selection: `/cmd` runs now; a mention replaces its token.
---@return boolean consumed
function M.accept()
  local item = popup.selected()
  if not popup.is_visible() or not item then
    return false
  end
  local win = vim.api.nvim_get_current_win()
  if not (win and vim.api.nvim_win_is_valid(win)) then
    popup.hide()
    return false
  end
  local input_buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1], cursor[2]
  local line = vim.api.nvim_buf_get_lines(input_buf, row - 1, row, false)[1] or ""
  local kind, _, start_col, end_col = trigger.detect(line, col)
  if not kind or start_col == nil then
    popup.hide()
    return false
  end
  local insert
  if kind == "command" then
    insert = ""
  elseif kind == "file" then
    insert = "@" .. item.value .. " "
  else
    insert = trigger.sign(kind) .. item.value .. " "
  end
  local new_line, new_col = trigger.replace(line, start_col, end_col, insert)
  vim.api.nvim_buf_set_lines(input_buf, row - 1, row, false, { new_line })
  pcall(vim.api.nvim_win_set_cursor, win, { row, new_col })
  popup.hide()
  if kind == "command" then
    require("agent.chat").send("/" .. item.value)
  end
  return true
end

--- Arm the triggers for `input_buf` (35 ms debounce; one group, no duplicates).
---@param input_buf integer
---@param input_win integer
function M.arm(input_buf, input_win)
  local group = vim.api.nvim_create_augroup("ChatCompletion", { clear = true })
  local timer
  local function stop()
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    buffer = input_buf,
    callback = function()
      stop()
      timer = vim.uv.new_timer()
      timer:start(
        35,
        0,
        vim.schedule_wrap(function()
          stop()
          M.sync(input_buf, input_win)
        end)
      )
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "WinLeave", "CursorMovedI" }, {
    group = group,
    buffer = input_buf,
    callback = function()
      local win = input_win
      if not (win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() == win) then
        M.hide()
      end
    end,
  })
end

return M
