-- ── Sessions (persistence.nvim): helpers for menus and dashboard ──────────────
local log = require "utils.log"

local M = {}

---@return table? persistence
local function persistence()
  local ok, p = pcall(require, "persistence")
  return ok and p or nil
end

--- Session file for this folder: the current branch's and, if none, the
--- main branch's (same order `persistence.load` uses).
---@return string?
local function current_file()
  local p = persistence()
  if not p then
    return nil
  end
  for _, file in ipairs { p.current(), p.current { branch = false } } do
    if vim.fn.filereadable(file) == 1 then
      return file
    end
  end
end

---@return boolean there is a saved session for this folder
function M.exists()
  return current_file() ~= nil
end

function M.restore()
  if not M.exists() then
    return log.warn "No saved session for this folder"
  end
  persistence().load()
end

--- Pick a session from any project (changes folder and restores it)
function M.pick()
  local p = persistence()
  if p then
    p.select()
  end
end

--- Restore the last saved session (from any project)
function M.last()
  local p = persistence()
  if not p or not p.last() then
    return log.warn "No saved sessions"
  end
  p.load { last = true }
end

function M.save()
  local p = persistence()
  if p then
    p.save()
    log.info "Session saved"
  end
end

--- Stop saving the session on exit (only for this nvim run)
function M.stop()
  local p = persistence()
  if p then
    p.stop()
    log.info "This session won't be saved on exit"
  end
end

--- Close the non-file windows (nvim-tree, aerial, trouble,
--- toggleterm, quickfix, help...) so they don't get saved in the session.
function M.close_auxiliary()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    local floating = vim.api.nvim_win_get_config(win).relative ~= ""
    if not floating and vim.bo[buf].buftype ~= "" and #vim.api.nvim_tabpage_list_wins(0) > 1 then
      pcall(vim.api.nvim_win_close, win, false)
    end
  end
end

return M
