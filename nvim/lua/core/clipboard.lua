-- ── Clipboard via OSC 52 ─────────────────────────────────────────────────────
-- Without a graphical server (WSL, SSH) wl-copy/xclip are useless; OSC 52 copies
-- through the terminal (herdr forwards it to Alacritty). Pasting uses the
-- unnamed register because Alacritty does not answer OSC 52 queries (system
-- paste is Ctrl+Shift+V in the terminal).
local settings = require "core.settings"

local M = {}

local function wanted()
  local mode = settings.clipboard.osc52
  if mode == "auto" then
    return vim.env.DISPLAY == nil and vim.env.WAYLAND_DISPLAY == nil
  end
  return mode == true
end

local function paste()
  return { vim.fn.split(vim.fn.getreg "", "\n"), vim.fn.getregtype "" }
end

function M.setup()
  -- The desktop app (app/) serves the system clipboard itself over RPC.
  if vim.g.leader_gui or not wanted() then
    return
  end
  local osc52 = require "vim.ui.clipboard.osc52"
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy "+", ["*"] = osc52.copy "*" },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end

return M
