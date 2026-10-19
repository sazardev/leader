-- ── The tests a buffer defines, with treesitter ──────────────────────────────
-- Every adapter lists its tests the same way: walk the tree, keep the nodes that are a test (a function named test_…,
-- a call to it()/test()/describe(), a #[test] fn, an XCTest method or a @Test function), with the names of what
-- encloses them (a class, a describe, a mod). The result is { id, name, line } per test: `id` is what the runner's
-- report says, so a result finds its line. Each adapter brings its own `visit`.
local M = {}

---@class LangTestDef
---@field id string      what the runner calls it ("TestCalc::test_add", "calc > adds", "tests::adds", "CalcTests.testAdd")
---@field name string    its own name ("test_add")
---@field line integer   1-based, where it starts
---@field last integer   1-based, where it ends
---@field kind "test"|"group"
---@field filter string? what selects it on the command line, when it differs from `id`

--- The root of a buffer's tree in a language, nil when there is no parser
---@param buf integer
---@param lang string
---@return TSNode?
function M.root(buf, lang)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not ok or not parser then
    return nil
  end
  local tree = parser:parse()[1]
  return tree and tree:root() or nil
end

---@param node TSNode?
---@param buf integer
---@return string
function M.text(node, buf)
  return node and vim.treesitter.get_node_text(node, buf) or ""
end

--- Walks the tree depth first. `visit(node, scope)` returns the scope its children get (a new table to open a scope,
--- or nil to keep the parent's): scopes are the enclosing names
---@param node TSNode
---@param visit fun(node: TSNode, scope: string[]): string[]?
---@param scope string[]?
function M.walk(node, visit, scope)
  scope = scope or {}
  for child in node:iter_children() do
    if child:named() then
      local inner = visit(child, scope) or scope
      M.walk(child, visit, inner)
    end
  end
end

--- The test (or group) whose lines hold `row`: the innermost one (the latest start at or before it, still open)
---@param defs LangTestDef[]
---@param row integer 1-based
---@return LangTestDef?
function M.nearest(defs, row)
  local best
  for _, d in ipairs(defs) do
    if row >= d.line and row <= d.last and (not best or d.line >= best.line) then
      best = d
    end
  end
  return best
end

--- A string literal's content: 'x', "x", `x` (no interpolation)
---@param text string
---@return string?
function M.literal(text)
  local q = text:sub(1, 1)
  if (q == '"' or q == "'" or q == "`") and text:sub(-1) == q and not (q == "`" and text:find("${", 1, true)) then
    return text:sub(2, -2)
  end
end

return M
