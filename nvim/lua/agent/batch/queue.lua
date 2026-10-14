-- ── The proposal queue ───────────────────────────────────────────────────────
-- Proposals produced in a row (a batch) wait here: jump between them (across files), accept them all at once, or see
-- the list in the quickfix. It does not own any proposal: the replace presenter does (`pending`, `accept_proposal`); this
-- is only the way to move through them.
local log = require "utils.log"

local M = {}

--- Where the queue lives in the leader menu (menus/agent_advanced.lua binds these; the notes quote them)
M.KEYS = { next = "]", previous = "[", accept_all = "y", list = "l" }

---@param name "next"|"previous"|"accept_all"|"list"
---@return string e.g. "<leader>aA]"
function M.label(name)
  return "<leader>aA" .. M.KEYS[name]
end

local function replace()
  return require "agent.output.replace"
end

---@param p AgentProposal
---@return integer? first line of the proposal in its buffer
local function first_line(p)
  return (require("agent.anchor").range(p.job.buf, p.job.anchor))
end

--- Goes to proposal number `index` (1-based, wraps)
---@param list AgentProposal[]
---@param index integer
---@param quiet boolean? no "proposal 2 of 3" line (the batch already said how many)
local function go(list, index, quiet)
  index = ((index - 1) % #list) + 1
  local p = list[index]
  local line = first_line(p)
  if not line then
    return log.warn "Agent: that proposal's code is gone"
  end
  if vim.api.nvim_get_current_buf() ~= p.job.buf then
    local win = vim.fn.bufwinid(p.job.buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.api.nvim_set_current_buf(p.job.buf)
    end
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
  vim.cmd "normal! zz"
  if #list > 1 and not quiet then
    log.info(("Agent: proposal %d of %d · %s"):format(index, #list, p.job.action.label))
  end
end

--- The position of the proposal the cursor is in (or the last one before it), 0 if none
---@param list AgentProposal[]
---@return integer
local function here(list)
  local buf, row = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1]
  local found = 0
  for i, p in ipairs(list) do
    if p.job.buf == buf then
      local first, last = require("agent.anchor").range(buf, p.job.anchor)
      if first and row >= first and row <= last then
        return i
      end
      if first and first <= row then
        found = i
      end
    end
  end
  return found
end

---@param dir 1|-1
function M.step(dir)
  local list = replace().pending()
  if #list == 0 then
    return log.info "Agent: no proposals waiting"
  end
  local at = here(list)
  go(list, at == 0 and (dir == 1 and 1 or #list) or at + dir)
end

--- Accepts every proposal waiting, after one question
function M.accept_all()
  local list = replace().pending()
  if #list == 0 then
    return log.info "Agent: no proposals waiting"
  end
  local hl = require("utils.modal").hl
  local files = {}
  for _, p in ipairs(list) do
    local name = vim.fn.fnamemodify(p.job.target.path, ":t")
    files[name] = (files[name] or 0) + 1
  end
  local lines = { { { ("Accept %d proposal%s?"):format(#list, #list == 1 and "" or "s") } }, "" }
  for name, n in pairs(files) do
    lines[#lines + 1] = { { "  " }, { name, hl.folder }, { ("  %d"):format(n), hl.muted } }
  end
  require("utils.modal").confirm(lines, { title = "Accept all", confirm = "Accept all" }, function()
    local accepted = 0
    for _, p in ipairs(list) do
      if replace().accept_proposal(p, { keep_cursor = true }) then
        accepted = accepted + 1
      end
    end
    log.info(("Agent: %d of %d accepted (u undoes each one)"):format(accepted, #list))
  end)
end

--- The proposals as a quickfix list
function M.list()
  local list = replace().pending()
  if #list == 0 then
    return log.info "Agent: no proposals waiting"
  end
  local items = {}
  for _, p in ipairs(list) do
    items[#items + 1] = {
      bufnr = p.job.buf,
      lnum = first_line(p) or 1,
      text = ("%s · %s"):format(p.job.action.label, p.job.target.name or p.job.target.kind),
    }
  end
  vim.fn.setqflist({}, " ", { title = "Agent proposals", items = items })
  vim.cmd "copen"
end

--- After a batch: if there is more than one proposal, go to the first
function M.open()
  local list = replace().pending()
  if #list > 0 then
    go(list, 1, true)
  end
end

return M
