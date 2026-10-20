-- ── Formatting on save: when it may block ────────────────────────────────────
-- Formatting before the write is deterministic (the file on disk is always formatted, nothing jumps afterwards) but it
-- holds the editor for as long as the formatter takes, and that grows with the file: 15k lines took ~1.9 s with a
-- language server's formatter. Past `settings.format_on_save.async_over_lines` the buffer is written at once and
-- formatted in the background, then written again (conform's `format_after_save`).
local settings = require "core.settings"

local M = {}

--- Pure: how should a buffer of `lines` lines be formatted when it is saved?
---@param lines integer
---@param cfg? { enabled: boolean, async_over_lines: integer }
---@return "sync"|"async"|nil mode nil = not at all
function M.mode(lines, cfg)
  cfg = cfg or settings.format_on_save
  if not cfg.enabled then
    return nil
  end
  return lines > cfg.async_over_lines and "async" or "sync"
end

--- conform's `format_on_save` option (a function: the settings panel can turn it off and on without a restart)
---@param buf integer
---@return table?
function M.on_save(buf)
  if M.mode(vim.api.nvim_buf_line_count(buf)) == "sync" then
    return { timeout_ms = settings.format_on_save.timeout_ms, lsp_format = "fallback" }
  end
end

--- conform's `format_after_save` option: the big buffers, formatted without holding the editor
---@param buf integer
---@return table?
function M.after_save(buf)
  if M.mode(vim.api.nvim_buf_line_count(buf)) == "async" then
    return { lsp_format = "fallback" }
  end
end

return M
