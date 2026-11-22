-- ── basedpyright: warm up imported modules ──────────────────────────────────
-- basedpyright builds a module's symbol table the FIRST time it is asked for attribute completions: 1–2.5 s for
-- pandas/numpy/matplotlib, then 5–10 ms for every later request. Ask for those completions just after the server
-- attaches (fire and forget), so the cost lands while the file opens, never while typing. One request per imported
-- alias; the answer is thrown away. Nothing runs in light mode (there is no server to attach).

local M = {}
local imports = require "utils.pyimports"

--- One completion position right after `alias.` for each imported alias, in file order, deduplicated by alias.
--- Pure: `lines` are the buffer's lines; line and character are 0-based (character = just after the dot).
--- A word ending in the alias (`xpd.`) is not a use of `pd`.
---@param lines string[]
---@param max? integer maximum number of aliases (default 8)
---@return { alias: string, line: integer, character: integer }[]
function M.targets(lines, max)
  local limit = max or 8
  local aliases, found, out = imports.aliases(lines), {}, {}
  for i, line in ipairs(lines) do
    if #out < limit then
      for alias in pairs(aliases) do
        if not found[alias] then
          local from = 1
          while true do
            local s, e = line:find(alias .. ".", from, true)
            if not s then
              break
            end
            if s == 1 or not line:sub(s - 1, s - 1):match "[%w_]" then
              found[alias] = true
              out[#out + 1] = { alias = alias, line = i - 1, character = e }
              break
            end
            from = e + 1
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.line < b.line or (a.line == b.line and a.character < b.character)
  end)
  return out
end

--- Fire (and ignore) one completion request per imported alias of `bufnr`.
---@param bufnr integer
---@param client vim.lsp.Client
function M.warm(bufnr, client)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines > 2000 then -- a minified/generated file is not worth warming
    return
  end
  local uri = vim.uri_from_bufnr(bufnr)
  for _, target in ipairs(M.targets(lines)) do
    pcall(client.request, client, "textDocument/completion", {
      textDocument = { uri = uri },
      position = { line = target.line, character = target.character },
    }, function() end, bufnr)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("BasedpyrightPrewarm", { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if not client or client.name ~= "basedpyright" or vim.bo[args.buf].filetype ~= "python" then
        return
      end
      -- A restart gives the client a new id; warm again, but never twice for the same client.
      if vim.b[args.buf].basedpyright_prewarm_client == client.id then
        return
      end
      vim.b[args.buf].basedpyright_prewarm_client = client.id
      vim.defer_fn(function()
        M.warm(args.buf, client)
      end, 400)
    end,
  })
end

return M
