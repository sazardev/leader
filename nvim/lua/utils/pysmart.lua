-- ── Python import completion (blink source, `python` only) ─────────────────────
-- Typing `pd`, `np`, `train_test_split`, `Path`… offers the canonical import. Accepting it keeps the alias at the
-- cursor and adds the statement at the top of the file (pyimports.apply), so the two never fight over the undo block.
-- Prefixes that need a package which is not installed still show, with `uv add <pkg>` in the detail.
local imports = require "utils.pyimports"
local pydata = require "utils.pydata"

local M = {}
local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat
local Source = {}
Source.__index = Source

local function settings()
  return require("core.settings").python or {}
end

local function word_before(ctx)
  return ctx.line:sub(1, ctx.cursor[2]):match "[%w_]*$" or ""
end

local function range_of(ctx, word)
  return {
    start = { line = ctx.cursor[1] - 1, character = math.max(ctx.cursor[2] - #word, 0) },
    ["end"] = { line = ctx.cursor[1] - 1, character = ctx.cursor[2] },
  }
end

local function empty()
  return { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
end

---@param item table
---@param callback fun(item: table)
function M.resolve(item, callback)
  local resolved = vim.deepcopy(item)
  local line = item.data and item.data.import or item.label
  resolved.documentation = {
    kind = "markdown",
    value = "```python\n"
      .. line
      .. "\n```"
      .. (item.data and item.data.available == false and "\n\n· add it with `uv add`" or ""),
  }
  callback(resolved)
end

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "python"
end

function Source:resolve(item, callback)
  M.resolve(item, callback)
end

function Source:execute(ctx, item, callback, default_implementation)
  default_implementation()
  imports.apply(ctx.bufnr, { item.data and item.data.import or item.label })
  callback()
end

---@param ctx blink.cmp.Context
---@param callback fun(response: table)
function Source:get_completions(ctx, callback)
  local cfg = settings().imports or {}
  if cfg.enabled == false then
    return callback(empty())
  end
  -- inside a string (a file path, a query): leave it to the pydata source
  if pydata.string_context(ctx.line:sub(1, ctx.cursor[2])) then
    return callback(empty())
  end
  local word = word_before(ctx)
  if #word < 2 then
    return callback(empty())
  end
  local bufname = vim.api.nvim_buf_get_name(ctx.bufnr)
  local root = require("utils.python").root(vim.fs.dirname(bufname))
  local installed = imports.installed(root)
  local range = range_of(ctx, word)
  local items = {}
  for _, m in ipairs(imports.matches(word, installed)) do
    if m.available or cfg.suggest_missing ~= false then
      local kind = m.kind == "symbol" and KIND.Function or KIND.Module
      items[#items + 1] = {
        label = m.label,
        labelDetails = { description = m.detail },
        kind = kind,
        insertTextFormat = FORMAT.PlainText,
        textEdit = { newText = m.label, range = range },
        filterText = m.label .. " " .. m.row.id .. " " .. m.row.line,
        sortText = m.available and "1" .. m.label or "2" .. m.label,
        data = { import = m.row.line, available = m.available },
      }
    end
  end
  callback { is_incomplete_forward = false, is_incomplete_backward = false, items = items }
end

return M
