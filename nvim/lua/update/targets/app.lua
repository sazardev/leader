-- ── Update target: the desktop app (the `leader` binary) ─────────────────────
-- Only inside the app. Its newest version is the latest PUBLISHED release (a tag alone has no binary). Updating runs the
-- release's installer in a terminal over the editor: it replaces the binary (Linux lets a running program be replaced);
-- the new one starts the next time Leader opens.
local semver = require "update.semver"

local M = { id = "app", label = "Leader app" }

---@return string?
function M.current()
  local v = vim.g.leader_gui_version
  return type(v) == "string" and semver.parse(v) and v or nil
end

---@param info UpdateInfo
---@return string?
function M.latest(info)
  return info.release
end

---@param info UpdateInfo
---@param done fun(ok: boolean, message: string)
function M.apply(info, done)
  local cfg = require("core.settings").update or {}
  local url = ("https://github.com/%s/releases/latest/download/leader-installer.sh"):format(cfg.repo)
  local W, H = vim.o.columns, vim.o.lines
  local tw, th = math.min(W - 10, 100), math.min(18, H - 8)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((H - th) / 2),
    col = math.floor((W - tw) / 2),
    width = tw,
    height = th,
    style = "minimal",
    border = require("ui.flat").border(),
    title = { { " UPDATING THE APP ", "FlatModalTitle" } },
    title_pos = "left",
    zindex = 250,
  })
  vim.fn.jobstart({ "sh", "-c", ("curl -fsSL '%s' | bash"):format(url) }, {
    term = true,
    on_exit = vim.schedule_wrap(function(_, code)
      if code == 0 then
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        done(true, "app updated to " .. (info.release or "the latest") .. "; it starts the next time Leader opens")
      else
        vim.keymap.set({ "n", "t" }, "q", function()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end, { buffer = buf, nowait = true, desc = "Close" })
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_set_config(win, {
            title = { { " DID NOT FINISH · read above, q closes ", "FlatModalTitle" } },
            title_pos = "left",
          })
        end
        done(false, "the app installer did not finish")
      end
    end),
  })
  vim.cmd "startinsert"
end

return M
