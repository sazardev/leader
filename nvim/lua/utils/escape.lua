-- ── <Esc> closes whatever is in the way ──────────────────────────────────────
-- A hardcore keyboard never reaches for `:q` or `<leader>q` to get rid of a help page, the quickfix list, a hover, a
-- picker, a side panel or a stray float: Esc does it. One ordered chain (the global normal-mode <Esc>):
--   1. the diagnostic popup, the agent's answer window (the ones that never take focus)
--   2. the window you are in, when it is extra: a float, or a help / quickfix / panel / scratch split (never the last
--      window, never a file you are editing, never the file tree: Esc there only gives the focus back)
--   3. focusable floats left over elsewhere (a hover, a preview, a picker that lost focus)
--   4. going back after gd / grr, then clearing the search highlight (what it always did)
-- Telescope and every picker built on it close on the FIRST Esc, also from insert mode (core/telescope config).
-- `classify` is pure (tested); `dismiss` reads the editor and acts.
local M = {}

--- Panels and tools that live in a split and are never what you are editing.
M.PANELS = {
  help = true,
  qf = true,
  aerial = true,
  ["grug-far"] = true,
  checkhealth = true,
  Trouble = true,
  trouble = true,
  undotree = true,
  diff = true,
  man = true,
  fugitive = true,
  git = true,
  ["dap-view"] = true,
  ["dap-repl"] = true,
  DiffviewFiles = true,
  DiffviewFileHistory = true,
  lspinfo = true,
  tsplayground = true,
  query = true,
  ["gitsigns-blame"] = true,
  NeogitStatus = true,
}

--- Windows that keep their own Esc or are the thing you are working in.
M.OWN = { nvdash = true, leadersetup = true, market = true, NvimTree = true, TelescopePrompt = true }

---@class EscWindow
---@field floating boolean
---@field focusable boolean
---@field buftype string
---@field filetype string
---@field windows integer windows in the tab
---@field tabs integer tab pages
---@field modified boolean
---@field keep boolean? marked `vim.w.leader_keep` (an overlay that stays)

--- What Esc should do with the window you are in.
---@param w EscWindow
---@return "close"|"close_tab"|"focus_back"|nil
function M.classify(w)
  if w.keep then
    return nil
  end
  if w.filetype == "NvimTree" then
    return w.windows > 1 and "focus_back" or nil
  end
  if M.OWN[w.filetype] then
    return nil
  end
  if w.floating then
    -- a float that is a file you are editing (rare) is not thrown away
    if w.buftype == "" and w.modified then
      return nil
    end
    return "close"
  end
  if w.modified then
    return nil
  end
  local extra = M.PANELS[w.filetype]
    or w.buftype == "help"
    or w.buftype == "quickfix"
    or w.buftype == "nofile"
    or w.buftype == "prompt"
  if w.windows <= 1 then
    -- an extra page that has a tab to itself (:checkhealth, a diff view): the tab goes, never the last tab
    return (extra and w.tabs > 1) and "close_tab" or nil
  end
  if
    M.PANELS[w.filetype]
    or w.buftype == "help"
    or w.buftype == "quickfix"
    or w.buftype == "nofile"
    or w.buftype == "prompt"
  then
    return "close"
  end
  return nil
end

---@param win integer
---@return EscWindow
local function describe(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local config = vim.api.nvim_win_get_config(win)
  return {
    floating = config.relative ~= "",
    focusable = config.focusable ~= false,
    buftype = vim.bo[buf].buftype,
    filetype = vim.bo[buf].filetype,
    windows = #vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative == ""
    end, vim.api.nvim_tabpage_list_wins(0)),
    tabs = #vim.api.nvim_list_tabpages(),
    modified = vim.bo[buf].modified,
    keep = vim.w[win].leader_keep == true,
  }
end

---@param win integer
---@return boolean closed
local function close(win)
  return vim.api.nvim_win_is_valid(win) and pcall(vim.api.nvim_win_close, win, false)
end

--- Closes the window you are in when it is extra.
---@return boolean did something
function M.close_current()
  local win = vim.api.nvim_get_current_win()
  local what = M.classify(describe(win))
  if what == "close" then
    return close(win)
  elseif what == "close_tab" then
    return pcall(vim.cmd, "tabclose")
  elseif what == "focus_back" then
    vim.cmd "wincmd p"
    return true
  end
  return false
end

--- Closes the focusable floats that are not the window you are in (a hover, a preview, a picker without focus).
---@return boolean closed one
function M.close_floats()
  local current, any = vim.api.nvim_get_current_win(), false
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= current and vim.api.nvim_win_is_valid(win) then
      local d = describe(win)
      if d.floating and d.focusable and not d.keep and not M.OWN[d.filetype] and close(win) then
        any = true
      end
    end
  end
  return any
end

--- The global normal-mode <Esc>.
function M.dismiss()
  local diag = require "utils.diagblocks"
  if diag.close_popup() then
    return
  end
  -- the agent's answer window never takes focus, so its own <Esc> cannot hear you while you are in the code
  if package.loaded["agent.ui.float"] and require("agent.ui.float").dismiss() then
    return
  end
  if M.close_current() or M.close_floats() then
    return
  end
  if not require("utils.navigation").back() then
    vim.cmd "noh"
  end
end

return M
