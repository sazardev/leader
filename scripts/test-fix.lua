-- Pruebas de los dos niveles de fix del agente: `fix` (en línea: el diagnóstico de la línea del cursor) y
-- `fix_block` (la función entera). Objetivo, contexto de alrededor, objetos a los que apunta el diagnóstico
-- (tipo de la variable, vía LSP si hay gopls) y prompts. Hermético: sin red ni tokens.
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

-- ── registro ─────────────────────────────────────────────────────────────────
local inline, block = actions.get "fix", actions.get "fix_block"
eq("teclas: f en línea, F bloque", { inline.key, block.key }, { "f", "F" })
eq("alcance: diagnóstico / función", { inline.scope, block.scope }, { "diagnostic", "function" })
eq("ambos son fixes (resuelven findings al aceptar)", { inline.fixes, block.fixes }, { true, true })
eq("en línea lee lo de alrededor; el bloque ya lo lleva en el objetivo", {
  vim.tbl_contains(inline.context, "around"),
  vim.tbl_contains(block.context, "around"),
}, { true, false })
eq("ambos leen diagnostics, findings, types y callees", {
  vim.tbl_contains(inline.context, "types") and vim.tbl_contains(inline.context, "callees"),
  vim.tbl_contains(block.context, "types") and vim.tbl_contains(block.context, "callees"),
}, { true, true })
local keys = {}
for _, a in ipairs(actions.list()) do
  keys[a.key] = (keys[a.key] or 0) + 1
end
eq(
  "ninguna tecla repetida en <leader>a",
  vim.tbl_filter(function(n)
    return n > 1
  end, keys),
  {}
)

-- ── proyecto Go temporal ─────────────────────────────────────────────────────
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ "module example.com/p", "", "go 1.21" }, dir .. "/go.mod")
vim.fn.writefile({
  "package p",
  "",
  "// Note es la nota.",
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
-- el proveedor `types` solo lee archivos del proyecto (raíz = .git o el cwd)
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

-- ── objetivo: las líneas del diagnóstico ─────────────────────────────────────
vim.api.nvim_win_set_cursor(0, { 9, 0 })
local t = target_mod.resolve(buf, "diagnostic")
eq("inline: el objetivo es la línea del diagnóstico", t and { t.kind, t.first, t.last }, { "diagnostic", 9, 9 })
eq("inline: check pasa con diagnóstico", inline.check(t), nil)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
local none, err = target_mod.resolve(buf, "diagnostic")
eq(
  "inline: sin diagnóstico en la línea, error claro",
  { none, err and err:match "no diagnostic on this line" },
  { nil, "no diagnostic on this line" }
)
-- diagnóstico de varias líneas
set_diags { { lnum = 5, end_lnum = 7, col = 0, end_col = 1, message = "bloque", severity = D.WARN } }
vim.api.nvim_win_set_cursor(0, { 7, 0 })
t = target_mod.resolve(buf, "diagnostic")
eq("inline: un diagnóstico multilínea cubre todo su rango", { t.first, t.last }, { 6, 8 })
-- un hallazgo del agente también cuenta (son diagnósticos por atender)
local findings_ns = require("agent.output.findings").namespace()
set_diags {}
vim.diagnostic.set(
  findings_ns,
  buf,
  { { lnum = 12, col = 0, message = "magic number", severity = D.INFO, source = "agent" } }
)
vim.api.nvim_win_set_cursor(0, { 13, 0 })
t = target_mod.resolve(buf, "diagnostic")
eq("inline: también arregla un hallazgo del agente", t and { t.first, t.last }, { 13, 13 })
vim.diagnostic.reset(findings_ns, buf)
-- un diagnóstico enorme: solo lo que empieza en la línea, con tope
set_diags {
  { lnum = 0, end_lnum = 13, col = 0, end_col = 1, message = "todo el archivo", severity = D.HINT },
  { lnum = 8, end_lnum = 8, col = 0, end_col = 3, message = "esta línea", severity = D.ERROR },
}
vim.api.nvim_win_set_cursor(0, { 9, 0 })
t = target_mod.resolve(buf, "diagnostic")
eq("inline: un diagnóstico desmesurado no arrastra todo el archivo", { t.first, t.last }, { 9, 9 })

-- ── objetivo del bloque: la función entera ───────────────────────────────────
set_diags {
  { lnum = 8, col = 19, end_lnum = 8, end_col = 23, message = "n.Titl undefined", severity = D.ERROR, source = "lsp" },
}
vim.api.nvim_win_set_cursor(0, { 6, 0 })
local bt = target_mod.resolve(buf, block.scope)
eq(
  "bloque: el objetivo es la función aunque el diagnóstico esté en otra línea",
  bt and { bt.kind, bt.first, bt.last },
  { "function", 3, 10 }
)
eq("bloque: check pasa si hay diagnóstico dentro", block.check(bt), nil)
vim.api.nvim_win_set_cursor(0, { 13, 0 })
local ob = target_mod.resolve(buf, block.scope)
eq("bloque: función sin diagnósticos, no hace nada", block.check(ob), "no diagnostics in the target: nothing to fix")

-- ── contexto de alrededor ────────────────────────────────────────────────────
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
  "alrededor: arranca en la firma de la función",
  around_text and around_text:match "^func Title%(id int%) string {",
  "func Title(id int) string {"
)
eq("alrededor: lleva lo de antes (variables en ámbito) y marca dónde va el objetivo", {
  around_text:find("prefix := ", 1, true) ~= nil,
  around_text:find("[<target> lines 9-9 go here]", 1, true) ~= nil,
  around_text:find("n.Titl", 1, true) == nil, -- el objetivo no se repite
}, { true, true, true })
eq("alrededor: no sale de la función (no trae Other)", around_text:find("Other", 1, true), nil)
local fn_target = target_mod.resolve(buf, "function")
local nothing = "x"
around.collect(fn_target, function(x)
  nothing = x
end)
eq("alrededor: si el objetivo ya es la función, no aporta", nothing, nil)

-- ── prompts ──────────────────────────────────────────────────────────────────
local env = { target = t }
eq("prompt inline: solo las líneas del diagnóstico, alrededor de solo lectura", {
  inline.system(env):find("ONLY the problem", 1, true) ~= nil,
  inline.system(env):find("<around>", 1, true) ~= nil,
  inline.system(env):find("OUTPUT: one fenced block", 1, true) ~= nil,
}, { true, true, true })
eq("prompt bloque: mantiene el bloque coherente", {
  block.system(env):find("coherent", 1, true) ~= nil,
  block.system(env):find("<around>", 1, true) == nil,
}, { true, true })
local _, p = prompt.build(inline, t, { { name = "around", text = "ctx" } }, "keep the prefix")
eq("prompt inline: lleva el objetivo numerado por rango y la instrucción del usuario", {
  p:find('<target lines="9-9" kind="diagnostic">', 1, true) ~= nil,
  p:find("keep the prefix", 1, true) ~= nil,
}, { true, true })

-- ── objetos a los que apunta el diagnóstico (treesitter) ─────────────────────
local scopes = require "agent.context.scopes"
local ids = scopes.identifiers_in(buf, 8, 19, 8, 23) -- `Titl` en `n.Titl`
eq(
  "identificadores: el objeto del acceso va primero (x.Titl -> x), luego el miembro",
  vim.tbl_map(function(i)
    return i.name
  end, ids),
  { "n", "Titl" }
)
local types_provider = require "agent.context.providers.types"
t = target_mod.resolve(buf, "diagnostic")
eq(
  "types: los identificadores del diagnóstico salen del LSP, no de otros",
  vim.tbl_map(function(i)
    return i.name
  end, types_provider.diagnostic_identifiers(t)),
  { "n", "Titl" }
)
set_diags {}
eq("types: sin diagnóstico no hay nada que resolver", types_provider.diagnostic_identifiers(t), {})
set_diags {
  { lnum = 8, col = 19, end_lnum = 8, end_col = 23, message = "n.Titl undefined", severity = D.ERROR, source = "lsp" },
}

-- ── el tipo de la variable sale del LSP (gopls), aunque el código no nombre el tipo ──
if vim.fn.executable "gopls" == 1 then
  vim.lsp.start({ name = "gopls", cmd = { "gopls" }, root_dir = dir }, { bufnr = buf })
  local attached = vim.wait(60000, function()
    return #vim.lsp.get_clients { bufnr = buf, name = "gopls" } > 0
  end, 50)
  eq("gopls arranca", attached, true)
  -- espera a que el workspace esté cargado: typeDefinition responde con la ubicación de `Note`
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
  eq("types: el tipo de `n` (de otro archivo, no nombrado en el objetivo) viene del LSP", {
    out and out:find("type Note struct", 1, true) ~= nil,
    out and out:find("Title string", 1, true) ~= nil,
    out and out:find("note.go", 1, true) ~= nil,
  }, { true, true, true })
else
  print "skip gopls no instalado: se omite la prueba de typeDefinition"
end

vim.cmd.cd "/"
vim.fn.delete(dir, "rf")
print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
