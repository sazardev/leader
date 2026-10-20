-- ── Big files: plain text, instantly ─────────────────────────────────────────
-- Everything that follows the filetype (treesitter, LSP, folds, lint, formatters) grows with the size of the file: a
-- full tree-sitter parse costs ~2 µs a line and runs on the main thread. Past the limits in `settings.bigfile` the
-- filetype becomes `bigfile`, so none of it starts, and the buffer is tuned to stay responsive. Generated code, logs,
-- dumps and minified bundles are the usual cases; nobody reads them through a parser.
local settings = require "core.settings"

local M = {}

M.FILETYPE = "bigfile"

--- Pure: is a file of `size` bytes and `lines` lines too big to be treated as code?
---@param size integer bytes
---@param lines integer? number of lines when known (nil = unknown, the byte limit alone decides)
---@param cfg? { max_bytes: integer, minified_bytes: integer, minified_line: integer }
---@return boolean
function M.is_big(size, lines, cfg)
  cfg = cfg or settings.bigfile
  if not size or size <= 0 then
    return false
  end
  if size > cfg.max_bytes then
    return true
  end
  -- a minified bundle is small in bytes but one huge line: parsers and the regex syntax both choke on it
  return lines ~= nil and lines > 0 and size >= cfg.minified_bytes and size / lines >= cfg.minified_line
end

---@param bytes integer
---@return string
function M.human(bytes)
  if bytes >= 1024 * 1024 then
    return ("%.1f MB"):format(bytes / 1024 / 1024)
  end
  return ("%d KB"):format(math.ceil(bytes / 1024))
end

--- The buffer's options for a file nobody will parse: nothing that scans the text on every change or redraw.
---@param buf integer
local function tune(buf)
  vim.b[buf].bigfile = true
  vim.b[buf].completion = false -- blink.cmp
  vim.b[buf].minianimate_disable = true
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = 100
  vim.bo[buf].syntax = "off"
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local wo = vim.wo[win]
    wo.foldenable = false
    wo.foldmethod = "manual"
    wo.spell = false
    wo.cursorline = false
    wo.colorcolumn = ""
    wo.list = false
  end
end

function M.setup()
  if not settings.bigfile.enabled then
    return
  end
  vim.filetype.add {
    pattern = {
      -- runs for every file that is opened: one stat, and the line count only when the buffer is already loaded
      [".*"] = {
        function(path, buf)
          local stat = path and path ~= "" and vim.uv.fs_stat(path) or nil
          if not stat or stat.type ~= "file" then
            return nil
          end
          local lines = buf and buf > 0 and vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_line_count(buf) or nil
          if not M.is_big(stat.size, lines) then
            return nil
          end
          if buf and buf > 0 then
            vim.b[buf].bigfile_size = stat.size
          end
          return M.FILETYPE
        end,
        { priority = 100 },
      },
    },
  }
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("Bigfile", { clear = true }),
    pattern = M.FILETYPE,
    callback = function(ev)
      tune(ev.buf)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(ev.buf) then
          local size = vim.b[ev.buf].bigfile_size
          vim.notify(
            ("Big file%s: syntax, LSP, folds and completion are off to keep it fast."):format(size and (" (" .. M.human(size) .. ")") or ""),
            vim.log.levels.INFO
          )
        end
      end)
    end,
  })
end

return M
