-- ── Herdr: nvim registers as an "agent" so the pane reopens after a restart ──
-- Herdr restores agent panes with the command they report. Here nvim reports
-- `nvim +HerdrResume` (restores the folder's session) and releases it on exit,
-- so a normal `:q` doesn't reopen it. It only acts inside Herdr.
local M = {}

local SOURCE = "nvim"
local seq = 0

---@return boolean
local function inside_herdr()
  return vim.env.HERDR_ENV == "1" and (vim.env.HERDR_PANE_ID or "") ~= "" and (vim.env.HERDR_BIN_PATH or "") ~= ""
end

--- `--seq` must grow between reports and between nvim runs
local function next_seq()
  seq = seq + 1
  return tostring(os.time() * 1000 + seq)
end

---@param args string[] arguments after `pane`
---@return string[]
local function command(args)
  return vim.list_extend({ vim.env.HERDR_BIN_PATH, "pane" }, args)
end

--- Register this nvim in the pane (async, failures are ignored). It doesn't override a
--- real agent (Claude, Codex...) already occupying the pane: nvim may be opened from it.
function M.attach()
  if not inside_herdr() or #vim.api.nvim_list_uis() == 0 then
    return
  end
  vim.system(command { "get", vim.env.HERDR_PANE_ID }, { text = true }, function(got)
    -- the callback runs in a "fast" context: vim.env and friends must be called scheduled
    vim.schedule(function()
      local ok, info = pcall(vim.json.decode, got.stdout or "")
      local pane = ok and type(info) == "table" and info.result and info.result.pane
      if not pane or (pane.agent ~= nil and pane.agent ~= vim.NIL) then
        return
      end
      vim.system(command {
        "report-agent", vim.env.HERDR_PANE_ID,
        "--source", SOURCE, "--agent", "nvim", "--state", "idle", "--seq", next_seq(),
        "--", "nvim", "+HerdrResume",
      })
    end)
  end)
end

--- Release the pane (synchronous and short: nvim is exiting)
function M.release()
  if not inside_herdr() or #vim.api.nvim_list_uis() == 0 then
    return
  end
  pcall(function()
    vim.system(command {
      "release-agent", vim.env.HERDR_PANE_ID, "--source", SOURCE, "--agent", "nvim", "--seq", next_seq(),
    }):wait(1000)
  end)
end

--- `nvim +HerdrResume`: restores the folder's session once nvim has started
--- (otherwise the dashboard opens on top of the restored session)
function M.resume()
  local function restore()
    local session = require "utils.session"
    if session.exists() then
      session.restore()
    end
  end
  if vim.v.vim_did_enter == 1 then
    return restore()
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.schedule(restore)
    end,
  })
end

return M
