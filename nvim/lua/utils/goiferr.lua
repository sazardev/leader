-- ── Go: `if err != nil` that knows what to return (no LLM, 0 tokens) ─────────
-- After a line that assigns an error (`n, err := s.repo.FindByID(ctx, id)`), it offers the ready-made block:
--   if err != nil {
--   	return nil, fmt.Errorf("find by id: %w", err)
--   }
-- · the zero values come from the RETURNS of the function containing the cursor (not from a fixed snippet);
-- · the message comes from the name of what was called (FindByID → "find by id"), editable as the first placeholder;
-- · in `main` (no return) it offers `log.Fatalf`; in a function that doesn't return error, it offers nothing.
-- It opens by itself on pressing Enter after that line (triggered by gosmart.autotrigger) and also when typing `if`/`iferr`.
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local FUNC_NODES = { function_declaration = true, method_declaration = true, func_literal = true }
local STATEMENT = {
  short_var_declaration = true,
  assignment_statement = true,
  expression_statement = true,
  var_declaration = true,
}

---@param row integer 1-based
---@param col integer 0-based
---@return TSNode?
local function node_at(row, col)
  local ok, node = pcall(function()
    vim.treesitter.get_parser(0, "go"):parse()
    return vim.treesitter.get_node { pos = { row - 1, math.max(col - 1, 0) } }
  end)
  return ok and node or nil
end

--- `FindByID` → "find by id", `GetHTTPServer` → "get http server"
---@param name string
---@return string
function M.words(name)
  local s = name:gsub("(%l)(%u)", "%1 %2"):gsub("(%u+)(%u%l)", "%1 %2")
  return s:lower()
end

--- Error variable assigned by a statement node and the call that produced it
---@param stmt TSNode
---@return string? var, string? call_name
local function assigned_error(stmt)
  local left = stmt:field("left")[1]
  if not left then
    return nil
  end
  local var
  local ids = left:type() == "expression_list" and left:named_children() or { left }
  for _, id in ipairs(ids) do
    local name = vim.treesitter.get_node_text(id, 0)
    if id:type() == "identifier" and (name:match "^err%w*$" or name:match "Err$") then
      var = name
    end
  end
  if not var then
    return nil
  end
  local right = stmt:field("right")[1]
  local call_name
  local function find(n)
    if call_name then
      return
    end
    if n:type() == "call_expression" then
      local fn = n:field("function")[1]
      if fn then
        local ident = fn:type() == "selector_expression" and fn:field("field")[1] or fn
        call_name = vim.treesitter.get_node_text(ident, 0)
      end
      return
    end
    for child in n:iter_children() do
      find(child)
    end
  end
  if right then
    find(right)
  end
  return var, call_name
end

--- Statement before the cursor: the last non-empty one above, climbing up to its statement node
---@param row integer
---@return TSNode?
local function previous_statement(row)
  local r = row - 1
  while r >= 1 do
    local line = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ""
    if line:match "%S" then
      local node = node_at(r, #line)
      while node and not STATEMENT[node:type()] do
        node = node:parent()
        if node and (node:type() == "block" or FUNC_NODES[node:type()]) then
          return nil -- the previous line is not a statement (`{`, `}`, a signature...)
        end
      end
      return node and STATEMENT[node:type()] and node or nil
    end
    r = r - 1
  end
end

---@class GoIfErrFunc
---@field results string[]
---@field is_main boolean

---@param node TSNode function_declaration | method_declaration | func_literal
---@param src integer|string
---@return GoIfErrFunc
local function func_info(node, src)
  local result = node:field("result")[1]
  local results = {}
  if result then
    if result:type() == "parameter_list" then
      for _, p in ipairs((ix.flat_params(result, src))) do
        results[#results + 1] = p.type
      end
    else
      results[1] = vim.treesitter.get_node_text(result, src)
    end
  end
  local name = node:field("name")[1]
  return {
    results = results,
    is_main = node:type() == "function_declaration"
      and name ~= nil
      and vim.treesitter.get_node_text(name, src) == "main",
  }
end

--- Returns of the function (or function literal) containing the position. If the body isn't closed yet (`{` without
--- `}`) the tree doesn't see them: the signature of the nearest column-0 `func` above is read.
---@param row integer
---@param col integer
---@return GoIfErrFunc?
local function enclosing(row, col)
  local node = node_at(row, col)
  while node and not FUNC_NODES[node:type()] do
    node = node:parent()
  end
  if node then
    return func_info(node, 0)
  end
  for r = row, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ""
    if line:match "^func%s" then
      local src = line:gsub("%s*{%s*$", "") .. " {}"
      local ok, parser = pcall(vim.treesitter.get_string_parser, src, "go")
      local decl = ok and parser:parse()[1]:root():named_child(0)
      if decl and (decl:type() == "function_declaration" or decl:type() == "method_declaration") then
        return func_info(decl, src)
      end
      return nil
    end
  end
end

---@param before string
---@return string?
local function fragment(before)
  return before:match "^%s*([%w_]*)$"
end

--- Is it a statement position with an error assigned right before? (the menu can open by itself there)
---@param ctx { line: string, cursor: integer[] }
---@return { var: string, call: string?, fn: GoIfErrFunc, frag: string }?
function M.context(ctx)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local frag = fragment(ctx.line:sub(1, col))
  if not frag then
    return nil
  end
  local stmt = previous_statement(row)
  if not stmt then
    return nil
  end
  local var, call = assigned_error(stmt)
  if not var then
    return nil
  end
  -- there is already an `if err` right below: don't offer another
  local below = vim.api.nvim_buf_get_lines(0, row, row + 3, false)
  for _, l in ipairs(below) do
    if l:match "%S" then
      if l:match("^%s*if%s+" .. var .. "%s*!=") then
        return nil
      end
      break
    end
  end
  local fn = enclosing(row, col)
  if not fn then
    return nil
  end
  return { var = var, call = call, fn = fn, frag = frag }
end

--- Blank line just opened after the assignment: used to open the menu without typing
---@param ctx { line: string, cursor: integer[] }
---@return boolean
function M.fresh(ctx)
  if ctx.line:match "%S" then
    return false
  end
  local info = M.context(ctx)
  return info ~= nil and (info.fn.is_main or (#info.fn.results > 0 and info.fn.results[#info.fn.results] == "error"))
end

---@param ctx { line: string, cursor: integer[] }
---@return table[]
function M.items(ctx)
  local info = M.context(ctx)
  if not info then
    return {}
  end
  local fn = info.fn
  local last = fn.results[#fn.results]
  if not fn.is_main and last ~= "error" then
    return {}
  end
  local frag = info.frag:lower()
  local function typed(word)
    return word:sub(1, #frag) == frag
  end
  if frag ~= "" and not (typed "if" or typed "iferr" or typed "err") then
    return {}
  end

  local row, col = ctx.cursor[1], ctx.cursor[2]
  local indent = #ctx.line:match "^%s*"
  local range = { start = { line = row - 1, character = indent }, ["end"] = { line = row - 1, character = col } }
  local msg = info.call and M.words(info.call) or "describe what failed"
  local zeros = {}
  if #fn.results > 1 then
    local pkg, path = ix.current_package()
    for i = 1, #fn.results - 1 do
      zeros[i] = pkg and ix.zero_for(fn.results[i], pkg, path) or ix.zero_value(fn.results[i], {}, {})
    end
  end
  local prefix = #zeros > 0 and (table.concat(zeros, ", ") .. ", ") or ""
  local v = info.var

  local function item(label, detail, body, order)
    return {
      label = label,
      labelDetails = { description = detail },
      kind = KIND.Snippet,
      insertTextFormat = FORMAT.Snippet,
      filterText = ("if %s != nil iferr err"):format(v),
      sortText = ("%03d"):format(order),
      documentation = {
        kind = "markdown",
        value = "```go\n" .. body:gsub("%${%d:([^}]*)}", "%1"):gsub("%$0", "") .. "\n```",
      },
      textEdit = { newText = body, range = range },
    }
  end

  local items = {}
  if fn.is_main then
    items[1] = item(
      ("if %s != nil"):format(v),
      "log.Fatalf",
      ('if %s != nil {\n\tlog.Fatalf("${1:%s}: %%v", %s)\n}\n$0'):format(v, ix.esc(msg), v),
      1
    )
  else
    items[1] = item(
      ("if %s != nil"):format(v),
      ("wrap · %s"):format(msg),
      ('if %s != nil {\n\treturn %sfmt.Errorf("${1:%s}: %%w", %s)\n}\n$0'):format(v, ix.esc(prefix), ix.esc(msg), v),
      1
    )
    items[2] = item(
      ("if %s != nil"):format(v),
      "return err",
      ("if %s != nil {\n\treturn %s%s\n}\n$0"):format(v, ix.esc(prefix), v),
      2
    )
  end
  return items
end

--- Is the cursor on the new line after `x, err := …`? (blink preselects the block: Enter accepts it). Turn it off with
--- `vim.g.goiferr_preselect = false`
---@return boolean
function M.active()
  if vim.g.goiferr_preselect == false or vim.bo.filetype ~= "go" or vim.api.nvim_get_mode().mode ~= "i" then
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  return M.fresh { line = vim.api.nvim_get_current_line(), cursor = { row, col } }
end

M._previous_statement, M._assigned_error = previous_statement, assigned_error

return M
