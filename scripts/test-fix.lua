-- Tests for the agent's two fix levels: `fix` (inline: the diagnostic on the cursor line) and
-- `fix_block` (the whole function). Target, surrounding context, objects the diagnostic points at
-- (variable type, via LSP if gopls is present) and prompts. Hermetic: no network or tokens.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end

local actions = require "agent.actions"
local target_mod = require "agent.context.target"
local context = require "agent.context"
local prompt = require "agent.prompt"

-- ── registry ─────────────────────────────────────────────────────────────────
local inline, block = actions.get "fix", actions.get "fix_block"
eq("keys: f inline, F block", { inline.key, block.key }, { "f", "F" })
eq("scope: diagnostic / function", { inline.scope, block.scope }, { "diagnostic", "function" })
eq("both are fixes (they resolve findings on accept)", { inline.fixes, block.fixes }, { true, true })
eq("inline reads the surroundings; the block already carries them in the target", {
  vim.tbl_contains(inline.context, "around"),
  vim.tbl_contains(block.context, "around"),
}, { true, false })
eq("both read diagnostics, findings, types and callees", {
  vim.tbl_contains(inline.context, "types") and vim.tbl_contains(inline.context, "callees"),
  vim.tbl_contains(block.context, "types") and vim.tbl_contains(block.context, "callees"),
}, { true, true })
local keys = {}
for _, a in ipairs(actions.list()) do
  local k = (a.advanced and "A" or "") .. a.key -- the Advanced menu (<leader>aA) has its own keys
  keys[k] = (keys[k] or 0) + 1
end
eq(
  "no repeated key in <leader>a",
  vim.tbl_filter(function(n)
    return n > 1
  end, keys),
  {}
)

-- ── temporary Go project ─────────────────────────────────────────────────────
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ "module example.com/p", "", "go 1.21" }, dir .. "/go.mod")
vim.fn.writefile({
  "package p",
  "",
  "// Note is the note.",
  "type Note struct {",
  "\tTitle string",
  "\tBody  string",
  "}",
  "",
  "func load() *Note { return nil }",
}, dir .. "/note.go")
local main = {
  "package p", -- 1
  "", -- 2
  "func Title(id int) string {", -- 3
  '\tprefix := "n:"', -- 4
  "\tn := load()", -- 5
  "\tif id < 0 {", -- 6
  '\t\treturn ""', -- 7
  "\t}", -- 8
  "\treturn prefix + n.Titl", -- 9
  "}", -- 10
  "", -- 11
  "func Other() int {", -- 12
  "\treturn 1", -- 13
  "}", -- 14
}
vim.fn.writefile(main, dir .. "/main.go")
-- the `types` provider only reads project files (root = .git or the cwd)
vim.cmd.cd(dir)
vim.cmd("edit " .. dir .. "/main.go")
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "go"
local ns = vim.api.nvim_create_namespace "test.fix"
local function set_diags(list)
  vim.diagnostic.set(ns, buf, list)
end
local D = vim.diagnostic.severity
set_diags {
  {
    lnum = 8,
    col = 19,
    end_lnum = 8,
    end_col = 25,
    message = "n.Titl undefined (no field or method Titl)",
    severity = D.ERROR,
    source = "lsp",
  },
}

-- ── target: the diagnostic lines ─────────────────────────────────────
vim.api.nvim_win_set_cursor(0, { 9, 0 })
local t = target_mod.resolve(buf, "diagnostic")
eq("inline: the target is the diagnostic line", t and { t.kind, t.first, t.last }, { "diagnostic", 9, 9 })
eq("inline: check passes with a diagnostic", inline.check(t), nil)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
local none, err = target_mod.resolve(buf, "diagnostic")
eq(
  "inline: with no diagnostic on the line, a clear error",
  { none, err and err:match "no diagnostic on this line" },
  { nil, "no diagnostic on this line" }
)
-- multi-line diagnostic
set_diags { { lnum = 5, end_lnum = 7, col = 0, end_col = 1, message = "block", severity = D.WARN } }
vim.api.nvim_win_set_cursor(0, { 7, 0 })
t = target_mod.resolve(buf, "diagnostic")
eq("inline: a multi-line diagnostic covers its whole range", { t.first, t.last }, { 6, 8 })
-- an agent finding also counts (they are diagnostics to attend to)
local findings_ns = require("agent.output.findings").namespace()
set_diags {}
vim.diagnostic.set(
  findings_ns,
  buf,
  { { lnum = 12, col = 0, message = "magic number", severity = D.INFO, source = "agent" } }
)
vim.api.nvim_win_set_cursor(0, { 13, 0 })
t = target_mod.resolve(buf, "diagnostic")
eq("inline: also fixes an agent finding", t and { t.first, t.last }, { 13, 13 })
vim.diagnostic.reset(findings_ns, buf)
-- a huge diagnostic: only what starts on the line, with a cap
set_diags {
  { lnum = 0, end_lnum = 13, col = 0, end_col = 1, message = "whole file", severity = D.HINT },
  { lnum = 8, end_lnum = 8, col = 0, end_col = 3, message = "this line", severity = D.ERROR },
}
vim.api.nvim_win_set_cursor(0, { 9, 0 })
t = target_mod.resolve(buf, "diagnostic")
eq("inline: an oversized diagnostic does not drag in the whole file", { t.first, t.last }, { 9, 9 })

-- ── block target: the whole function ───────────────────────────────────
set_diags {
  { lnum = 8, col = 19, end_lnum = 8, end_col = 23, message = "n.Titl undefined", severity = D.ERROR, source = "lsp" },
}
vim.api.nvim_win_set_cursor(0, { 6, 0 })
local bt = target_mod.resolve(buf, block.scope)
eq(
  "block: the target is the function even if the diagnostic is on another line",
  bt and { bt.kind, bt.first, bt.last },
  { "function", 3, 10 }
)
eq("block: check passes if there is a diagnostic inside", block.check(bt), nil)
vim.api.nvim_win_set_cursor(0, { 13, 0 })
local ob = target_mod.resolve(buf, block.scope)
eq("block: function without diagnostics, does nothing", block.check(ob), "no diagnostics in the target: nothing to fix")

-- ── surrounding context ────────────────────────────────────────────────────
local function section(a, tg, name)
  local out
  context.build(a, tg, function(sections)
    for _, s in ipairs(sections) do
      if s.name == name then
        out = s.text
      end
    end
    out = out or false
  end)
  vim.wait(3000, function()
    return out ~= nil
  end, 20)
  return out
end
vim.api.nvim_win_set_cursor(0, { 9, 0 })
t = target_mod.resolve(buf, "diagnostic")
local around = require "agent.context.providers.around"
local around_text
around.collect(t, function(x)
  around_text = x
end)
eq(
  "around: starts at the function signature",
  around_text and around_text:match "^func Title%(id int%) string {",
  "func Title(id int) string {"
)
eq("around: carries what comes before (variables in scope) and marks where the target goes", {
  around_text:find("prefix := ", 1, true) ~= nil,
  around_text:find("[<target> lines 9-9 go here]", 1, true) ~= nil,
  around_text:find("n.Titl", 1, true) == nil, -- the target is not repeated
}, { true, true, true })
eq("around: does not leave the function (does not bring Other)", around_text:find("Other", 1, true), nil)
local fn_target = target_mod.resolve(buf, "function")
local nothing = "x"
around.collect(fn_target, function(x)
  nothing = x
end)
eq("around: if the target is already the function, it contributes nothing", nothing, nil)

-- ── prompts ──────────────────────────────────────────────────────────────────
local env = { target = t }
eq("inline prompt: only the diagnostic lines, read-only surroundings", {
  inline.system(env):find("ONLY the problem", 1, true) ~= nil,
  inline.system(env):find("<around>", 1, true) ~= nil,
  inline.system(env):find("OUTPUT: one fenced block", 1, true) ~= nil,
}, { true, true, true })
eq("block prompt: keeps the block coherent", {
  block.system(env):find("coherent", 1, true) ~= nil,
  block.system(env):find("<around>", 1, true) == nil,
}, { true, true })
local _, p = prompt.build(inline, t, { { name = "around", text = "ctx" } }, "keep the prefix")
eq("inline prompt: carries the target numbered by range and the user instruction", {
  p:find('<target lines="9-9" kind="diagnostic">', 1, true) ~= nil,
  p:find("keep the prefix", 1, true) ~= nil,
}, { true, true })

-- ── objects the diagnostic points at (treesitter) ─────────────────────
local scopes = require "agent.context.scopes"
local ids = scopes.identifiers_in(buf, 8, 19, 8, 23) -- `Titl` in `n.Titl`
eq(
  "identifiers: the accessed object comes first (x.Titl -> x), then the member",
  vim.tbl_map(function(i)
    return i.name
  end, ids),
  { "n", "Titl" }
)
local types_provider = require "agent.context.providers.types"
t = target_mod.resolve(buf, "diagnostic")
eq(
  "types: the diagnostic's identifiers come from the LSP, not others",
  vim.tbl_map(function(i)
    return i.name
  end, types_provider.diagnostic_identifiers(t)),
  { "n", "Titl" }
)
set_diags {}
eq("types: without a diagnostic there is nothing to resolve", types_provider.diagnostic_identifiers(t), {})
set_diags {
  { lnum = 8, col = 19, end_lnum = 8, end_col = 23, message = "n.Titl undefined", severity = D.ERROR, source = "lsp" },
}

-- ── the variable's type comes from the LSP (gopls), even if the code does not name the type ──
if vim.fn.executable "gopls" == 1 then
  vim.lsp.start({ name = "gopls", cmd = { "gopls" }, root_dir = dir }, { bufnr = buf })
  local attached = vim.wait(60000, function()
    return #vim.lsp.get_clients { bufnr = buf, name = "gopls" } > 0
  end, 50)
  eq("gopls starts", attached, true)
  -- wait for the workspace to load: typeDefinition answers with the location of `Note`
  local out
  vim.wait(60000, function()
    out = nil
    local ok, e = pcall(types_provider.collect, t, function(x)
      out = x or false
    end, { action = inline, names = inline.context })
    if not ok then
      print("ERR", e)
    end
    vim.wait(2000, function()
      return out ~= nil
    end, 20)
    return out and out:find("Note", 1, true) ~= nil
  end, 500)
  eq("types: the type of `n` (from another file, not named in the target) comes from the LSP", {
    out and out:find("type Note struct", 1, true) ~= nil,
    out and out:find("Title string", 1, true) ~= nil,
    out and out:find("note.go", 1, true) ~= nil,
  }, { true, true, true })
else
  print "skip gopls not installed: the typeDefinition test is skipped"
end

vim.cmd.cd "/"
vim.fn.delete(dir, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
