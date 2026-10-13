-- ── Standard documentation comments ──────────────────────────────────────────
-- Idiomatic doc template for the language for the function/type under the cursor, built with
-- treesitter (name, parameters, return): no AI, instant and always the same format.
-- To write the content use the agent's `docs` action (<leader>ad).
--
-- Languages: go (godoc), lua (LuaCATS), typescript/javascript (JSDoc), python (Google docstring),
-- rust (rustdoc). To add one: an entry in LANGS (`placement` + `build`) and, if its
-- "public" declarations aren't "all", a rule in PUBLIC.
local blocks = require "utils.blocks"
local log = require "utils.log"
local scopes = require "agent.context.scopes"

local M = {}

-- anonymous functions: a `return` inside one doesn't count for the outer function
local FUNCTION_NODES = {
  function_declaration = true,
  function_definition = true,
  function_expression = true,
  function_item = true,
  function_literal = true,
  arrow_function = true,
  method_definition = true,
  method_declaration = true,
  closure_expression = true,
  lambda = true,
}

---@param node TSNode
---@return boolean
local function returns_value(node)
  local found = false
  local function walk(n, top)
    if found then
      return
    end
    if not top and FUNCTION_NODES[n:type()] then
      return
    end
    if n:type() == "return_statement" and n:named_child_count() > 0 then
      found = true
      return
    end
    for child in n:iter_children() do
      walk(child, false)
    end
  end
  walk(node, true)
  return found
end

--- `export function f` and `@deco def f` are captured wrapped: the real declaration is inside
---@param node TSNode
---@return TSNode
local function decl_of(node)
  return node:field("declaration")[1] or node:field("definition")[1] or node
end

---@param node TSNode
---@param buf integer
---@return string?
local function name_of(node, buf)
  local field = node:field("name")[1]
  if not field then
    -- Go: `type_declaration` keeps the name in its `type_spec`
    for child in node:iter_children() do
      field = child:field("name")[1]
      if field then
        break
      end
    end
  end
  return field and vim.treesitter.get_node_text(field, buf) or nil
end

local SKIP_PARAMS = { self = true, cls = true, this = true, _ = true }

--- Parameter names, in order
---@param node TSNode
---@param buf integer
---@return string[]
local function param_names(node, buf)
  local list = node:field("parameters")[1]
  local names = {}
  if not list then
    return names
  end
  local function add(n)
    local name = vim.treesitter.get_node_text(n, buf)
    if not SKIP_PARAMS[name] then
      names[#names + 1] = name
    end
  end
  for param in list:iter_children() do
    if param:named() and not param:type():find "comment" then
      local fields = param:field "name"
      if #fields == 0 then
        fields = param:field "pattern"
      end
      if #fields > 0 then
        vim.tbl_map(add, fields) -- Go: `a, b int` carries several names
      elseif param:type() == "identifier" then
        add(param)
      else
        for child in param:iter_children() do
          if child:type() == "identifier" then
            add(child)
            break
          end
        end
      end
    end
  end
  return names
end

---@class DocInfo
---@field name string?
---@field params string[]
---@field returns boolean
---@field kind "function"|"class"
---@field node TSNode
---@field indent string

--- Each language: where the comment goes and the lines that get inserted.
--- `cursor` = { relative line (1-based), column } where the cursor lands to start writing.
---@type table<string, { placement: "above"|"inside", build: fun(i: DocInfo): string[], cursor: integer[] }>
local LANGS = {
  go = {
    placement = "above",
    build = function(i)
      return { "// " .. (i.name or "") .. " " }
    end,
    cursor = { 1, -1 },
  },
  lua = {
    placement = "above",
    build = function(i)
      local lines = { "--- " }
      for _, p in ipairs(i.params) do
        lines[#lines + 1] = "---@param " .. p .. " any"
      end
      if i.returns then
        lines[#lines + 1] = "---@return any"
      end
      return lines
    end,
    cursor = { 1, -1 },
  },
  typescript = {
    placement = "above",
    build = function(i)
      local lines = { "/**", " * " }
      if #i.params > 0 or i.returns then
        lines[#lines + 1] = " *"
      end
      for _, p in ipairs(i.params) do
        lines[#lines + 1] = " * @param " .. p .. " "
      end
      if i.returns then
        lines[#lines + 1] = " * @returns "
      end
      lines[#lines + 1] = " */"
      return lines
    end,
    cursor = { 2, -1 },
  },
  python = {
    placement = "inside",
    build = function(i)
      -- the cursor lands after the opening quotes to write the summary
      local lines = { '"""', "" }
      if #i.params > 0 then
        lines[#lines + 1] = "Args:"
        for _, p in ipairs(i.params) do
          lines[#lines + 1] = "    " .. p .. ": "
        end
        lines[#lines + 1] = ""
      end
      if i.returns then
        lines[#lines + 1] = "Returns:"
        lines[#lines + 1] = "    "
      end
      if lines[#lines] == "" then
        lines[#lines] = nil
      end
      lines[#lines + 1] = '"""'
      return lines
    end,
    cursor = { 1, -1 },
  },
  rust = {
    placement = "above",
    build = function(i)
      local lines = { "/// " }
      if #i.params > 0 then
        lines[#lines + 1] = "///"
        lines[#lines + 1] = "/// # Arguments"
        lines[#lines + 1] = "///"
        for _, p in ipairs(i.params) do
          lines[#lines + 1] = ("/// * `%s` - "):format(p)
        end
      end
      return lines
    end,
    cursor = { 1, -1 },
  },
}
LANGS.javascript = LANGS.typescript
LANGS.tsx = LANGS.typescript
LANGS.typescriptreact = LANGS.typescript
LANGS.javascriptreact = LANGS.typescript

--- Does it count as public API? Without a rule for the language, everything counts.
---@type table<string, fun(node: TSNode, name: string, buf: integer): boolean>
local PUBLIC = {
  go = function(_, name)
    return name:match "^%u" ~= nil
  end,
  python = function(_, name)
    return not name:match "^_"
  end,
  lua = function(node, name)
    -- `local function` and local variables are internal: only M.x / M:x and globals
    return name:find "[.:]" ~= nil or node:parent() == nil or node:parent():type() ~= "chunk"
  end,
  rust = function(node)
    for child in node:iter_children() do
      if child:type() == "visibility_modifier" then
        return true
      end
    end
    return false
  end,
  typescript = function(node, name)
    local parent = node:parent()
    local exported = parent and parent:type() == "export_statement"
    return exported or node:type() == "method_definition" and not name:match "^[_#]"
  end,
}
PUBLIC.javascript = PUBLIC.typescript
PUBLIC.tsx = PUBLIC.typescript

local ATTACHED = { export_statement = true, decorated_definition = true }
local BEFORE = { attribute_item = true, decorator = true }

--- Node where the declaration visually starts (with `export`, decorators, attributes)
---@param node TSNode
---@return TSNode
local function anchor_node(node)
  local top = node
  while top:parent() and ATTACHED[top:parent():type()] do
    top = top:parent()
  end
  local prev = top:prev_sibling()
  while prev and BEFORE[prev:type()] do
    top = prev
    prev = top:prev_sibling()
  end
  return top
end

---@param buf integer
---@param root TSNode
---@param row integer 0-based; declaration row
---@return boolean
local function comment_above(buf, root, row)
  if row == 0 then
    return false
  end
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local col = line:find "%S"
  if not col then
    return false
  end
  local node = root:named_descendant_for_range(row - 1, col - 1, row - 1, col - 1)
  return node ~= nil and node:type():find "comment" ~= nil
end

--- Does the declaration already have documentation? (Python: docstring as first statement)
---@param buf integer
---@param root TSNode
---@param lang string
---@param node TSNode
---@return boolean
local function documented(buf, root, lang, node)
  if lang == "python" then
    local body = node:field("body")[1]
    local first = body and body:named_child(0)
    local str = first and first:type() == "expression_statement" and first:named_child(0)
    return str and str:type() == "string" or false
  end
  return comment_above(buf, root, (anchor_node(node):range()))
end

--- Insert the documentation template at the function/type under the cursor
function M.skeleton()
  local buf = vim.api.nvim_get_current_buf()
  local list = blocks.list(buf)
  local root, lang = scopes.parse(buf)
  if not (list and root and lang) then
    return log.warn "No treesitter parser for this buffer"
  end
  local spec = LANGS[lang]
  if not spec then
    return log.warn(("No doc template for %s yet. Use the agent: <leader>ad"):format(lang))
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local block
  for _, b in ipairs(list) do -- sorted by start: the last one containing the cursor is the innermost
    if b.first <= row and row <= b.last then
      block = b
    end
  end
  if not block then
    return log.warn "The cursor is not inside a function or type"
  end
  if documented(buf, root, lang, decl_of(block.node)) then
    return log.info "Already documented"
  end

  local node = decl_of(block.node)
  local anchor_row = (anchor_node(node):range())
  ---@type DocInfo
  local info = {
    name = name_of(node, buf),
    params = block.kind == "function" and param_names(node, buf) or {},
    returns = block.kind == "function"
      and (node:field("result")[1] ~= nil or node:field("return_type")[1] ~= nil or returns_value(node)),
    kind = block.kind,
    node = node,
    indent = "",
  }

  local lines, at
  if spec.placement == "inside" then
    local body = node:field("body")[1]
    if not body or body:start() == node:start() then
      return log.warn "Put the body on its own lines first"
    end
    local first_row = body:start()
    info.indent = (vim.api.nvim_buf_get_lines(buf, first_row, first_row + 1, false)[1] or ""):match "^%s*"
    lines, at = spec.build(info), first_row
  else
    info.indent = (vim.api.nvim_buf_get_lines(buf, anchor_row, anchor_row + 1, false)[1] or ""):match "^%s*"
    lines, at = spec.build(info), anchor_row
  end

  lines = vim.tbl_map(function(l)
    return l == "" and "" or info.indent .. l
  end, lines)
  vim.api.nvim_buf_set_lines(buf, at, at, false, lines)

  local cur_line = at + spec.cursor[1]
  vim.api.nvim_win_set_cursor(0, { cur_line, 0 })
  vim.cmd "startinsert!"
end

--- Public declarations without a doc comment → quickfix
function M.missing()
  local buf = vim.api.nvim_get_current_buf()
  local list = blocks.list(buf)
  local root, lang = scopes.parse(buf)
  if not (list and root and lang) then
    return log.warn "No treesitter parser for this buffer"
  end

  local rule = PUBLIC[lang]
  local items = {}
  for _, b in ipairs(list) do
    local node = decl_of(b.node)
    local name = name_of(node, buf)
    if name and (not rule or rule(node, name, buf)) and not documented(buf, root, lang, node) then
      items[#items + 1] = {
        bufnr = buf,
        lnum = (anchor_node(node):range()) + 1,
        col = 1,
        text = ("missing doc comment: %s"):format(name),
        type = "W",
      }
    end
  end
  if #items == 0 then
    return log.info "Every public function and type has a doc comment"
  end
  vim.fn.setqflist({}, " ", { title = "Missing doc comments", items = items })
  vim.cmd "copen"
end

return M
