-- Signatures of what the target CALLS, requested from the LSP (hover). It is the context that most
-- prevents hallucinations: the model sees each function's real signature instead of guessing it.
-- Asynchronous with a wait cap: whatever the LSP does not answer in time is omitted.
local settings = require("core.settings").agent.context
local scopes = require "agent.context.scopes"

local CALLEE_FIELDS = { "field", "property", "attribute", "method", "name" }

---@param node TSNode
---@return boolean
local function is_identifier(node)
  return node:type():find "identifier" ~= nil
end

--- The identifier naming the callee (`pkg.Fn(...)` -> Fn, `fn(...)` -> fn)
---@param fn TSNode
---@return TSNode?
local function callee_identifier(fn)
  if is_identifier(fn) then
    return fn
  end
  for _, field in ipairs(CALLEE_FIELDS) do
    local child = fn:field(field)[1]
    if child and is_identifier(child) then
      return child
    end
  end
  local last = fn:named_child(fn:named_child_count() - 1)
  return last and is_identifier(last) and last or nil
end

---@param target AgentTarget
---@return { name: string, row: integer, col: integer }[]
local function collect_callees(target)
  local root = scopes.parse(target.buf)
  if not root then
    return {}
  end
  local node = root:named_descendant_for_range(target.first - 1, 0, target.last - 1, 1000)
  local found, seen = {}, {}

  local function walk(n)
    if #found >= settings.callees then
      return
    end
    if n:type():find "call" then
      local fn = n:field("function")[1] or n:field("name")[1]
      local ident = fn and callee_identifier(fn)
      if ident then
        local name = vim.treesitter.get_node_text(ident, target.buf)
        local row, col = ident:start()
        if not seen[name] and row + 1 >= target.first and row + 1 <= target.last then
          seen[name] = true
          found[#found + 1] = { name = name, row = row, col = col }
        end
      end
    end
    for child in n:iter_children() do
      walk(child)
    end
  end
  if node then
    walk(node)
  end
  return found
end

--- The signature from a hover: the first code block, or the first two lines
---@param contents any
---@return string?
local function signature(contents)
  local lines = vim.lsp.util.convert_input_to_markdown_lines(contents)
  local md = table.concat(lines, "\n")
  local code = md:match "```[%w_]*\n(.-)\n```"
  local text = code
    or table.concat(
      vim.list_slice(
        vim.tbl_filter(function(l)
          return l:match "%S" and not l:match "^%-%-%-+$"
        end, lines),
        1,
        2
      ),
      "\n"
    )
  text = vim.trim(text)
  return text ~= "" and text:sub(1, 300) or nil
end

return {
  cap = 3000,
  stability = 2,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local clients = vim.lsp.get_clients { bufnr = target.buf, method = "textDocument/hover" }
    if #clients == 0 then
      return done(nil)
    end
    local callees = collect_callees(target)
    if #callees == 0 then
      return done(nil)
    end

    local encoding = clients[1].offset_encoding or "utf-16"
    local results, pending, finished = {}, #callees, false

    local function finish()
      if finished then
        return
      end
      finished = true
      local unique, seen = {}, {}
      for i = 1, #callees do
        local sig = results[i]
        if sig and not seen[sig] then
          seen[sig] = true
          unique[#unique + 1] = sig
        end
      end
      done(#unique > 0 and table.concat(unique, "\n\n") or nil)
    end

    vim.defer_fn(finish, settings.hover_timeout_ms)
    for i, callee in ipairs(callees) do
      local line = vim.api.nvim_buf_get_lines(target.buf, callee.row, callee.row + 1, false)[1] or ""
      local ok, character = pcall(vim.str_utfindex, line, encoding, callee.col)
      vim.lsp.buf_request(target.buf, "textDocument/hover", {
        textDocument = vim.lsp.util.make_text_document_params(target.buf),
        position = { line = callee.row, character = ok and character or callee.col },
      }, function(_, result)
        if result and result.contents then
          results[i] = signature(result.contents)
        end
        pending = pending - 1
        if pending == 0 then
          finish()
        end
      end)
    end
  end,
}
