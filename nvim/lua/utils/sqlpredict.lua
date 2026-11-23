-- ── Predictions from your own SQL history (blink source, `sql` only) ───────────
-- The queries you ran in this project are the best guess for the one you are writing. Typing three letters of a past
-- query offers its full text, ready to insert. Local, 0 tokens, capped by the history setting; no process, no network.
local M = {}
local KIND = vim.lsp.protocol.CompletionItemKind
local Source = {}
Source.__index = Source

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "sql"
end

local function empty()
  return { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
end

---@param ctx blink.cmp.Context
---@param callback fun(response: table)
function Source:get_completions(ctx, callback)
  local before = ctx.line:sub(1, ctx.cursor[2])
  if before:match "%.$" or require("utils.sqlkeywords").junk_context(before) then
    return callback(empty())
  end
  local word = before:match "[%w_]*$" or ""
  if #word < 3 then
    return callback(empty())
  end
  local name = vim.api.nvim_buf_get_name(ctx.bufnr)
  local dir = name ~= "" and vim.fs.dirname(vim.fn.fnamemodify(name, ":p")) or vim.fn.getcwd()
  local root = vim.fs.root(dir, { ".env", ".git", "config.yml", ".sqlfluff" }) or dir
  local history = require "sqlrun.history"
  local items = {}
  for _, entry in ipairs(history.load(root)) do
    local title = history.title(entry.text, 80)
    if title:lower():find(word:lower(), 1, true) then
      local line, col = ctx.cursor[1] - 1, ctx.cursor[2]
      items[#items + 1] = {
        label = title,
        kind = KIND.Snippet,
        detail = "query · " .. (entry.ok == false and "failed" or "ran"),
        textEdit = {
          range = {
            start = { line = line, character = math.max(col - #word, 0) },
            ["end"] = { line = line, character = col },
          },
          newText = entry.text,
        },
      }
      if #items >= 8 then
        break
      end
    end
  end
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return M
