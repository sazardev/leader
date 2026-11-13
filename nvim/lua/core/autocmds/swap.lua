-- ── Stale swap files ─────────────────────────────────────────────────────────
-- A swap file left by an editor that died (a crash, `kill -9`, a terminal closed under it) makes Neovim ask E325
-- every time the file is opened. Neovim 0.12's default handler only skips the prompt when the owner is still
-- running, and `swapinfo().pid` is 0 exactly when it is not. Remove that orphan (same user, readable) and edit the
-- file; a swap owned by another user, or one that cannot be read, still gets the normal prompt. A live owner keeps
-- its swap: the default handler has already chosen "edit" for it.
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("SwapExists", {
    group = vim.api.nvim_create_augroup("LeaderSwap", { clear = true }),
    callback = function()
      local info = vim.fn.swapinfo(vim.v.swapname)
      local user = vim.uv.os_get_passwd().username
      if info.error or info.user ~= user or info.pid ~= 0 then
        return
      end
      if vim.uv.fs_unlink(vim.v.swapname) then
        vim.v.swapchoice = "e"
        vim.notify(
          ("Removed a stale swap file: %s"):format(vim.fn.fnamemodify(vim.v.swapname, ":t")),
          vim.log.levels.INFO
        )
      end
    end,
  })
end

return M
