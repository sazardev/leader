-- Pruebas de las pruebas con el agente (<leader>aT) y de las lentes (<leader>aL): convenciones por lenguaje, destino
-- (final del archivo de pruebas), puertas que ahorran tokens, correr la prueba, huecos y el flujo entero por el
-- pipeline con un backend falso. Hermético: proyecto en un directorio temporal, estado en memoria, sin red ni tokens.
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
local function wait(fn, ms)
  return vim.wait(ms or 8000, fn, 20)
end

local conv = require "agent.tests.convention"
local run = require "agent.tests.run"
local dest = require "agent.tests.target"

-- ── convenciones (puro) ──────────────────────────────────────────────────────
local proj = vim.fn.tempname()
vim.fn.mkdir(proj .. "/src", "p")
vim.fn.mkdir(proj .. "/pkg/tests", "p")
vim.fn.mkdir(proj .. "/lib/ui", "p")
vim.fn.mkdir(proj .. "/app/src/main/java/x", "p")
vim.fn.writefile({}, proj .. "/.git") -- marca de raíz (archivo basta para vim.fs.root)
vim.fn.writefile({ '{ "devDependencies": { "vitest": "1" } }' }, proj .. "/package.json")
vim.fn.writefile({ "name: app", "dependencies:", "  flutter:" }, proj .. "/pubspec.yaml")

local function loc(rel, lang)
  local info, why = conv.locate(proj .. "/" .. rel, lang)
  return info and { vim.fn.fnamemodify(info.path, ":s?" .. proj .. "/??"), info.framework:match "^%S+", info.inline }
    or { nil, why }
end
eq("locate go: <nombre>_test.go junto al código", loc("pkg/store.go", "go")[1], "pkg/store_test.go")
eq("locate go: testing por defecto", loc("pkg/store.go", "go")[2], "Go")
eq(
  "locate ts: .test. y vitest según package.json",
  { loc("src/a.ts", "typescript")[1], loc("src/a.ts", "typescript")[2] },
  { "src/a.test.ts", "vitest" }
)
vim.fn.writefile({}, proj .. "/src/other.spec.ts")
eq("locate ts: si la carpeta ya usa .spec., lo sigue", loc("src/a.ts", "typescript")[1], "src/a.spec.ts")
eq("locate python: tests/ del proyecto si existe", loc("pkg/mod.py", "python")[1], "pkg/tests/test_mod.py")
eq("locate lua: _spec.lua", loc("lib/x.lua", "lua")[1], "lib/x_spec.lua")
eq(
  "locate rust: en el mismo archivo",
  { loc("src/lib.rs", "rust")[1], loc("src/lib.rs", "rust")[3] },
  { "src/lib.rs", true }
)
eq(
  "locate dart: lib/ pasa a test/ y flutter_test",
  { loc("lib/ui/btn.dart", "dart")[1], loc("lib/ui/btn.dart", "dart")[2] },
  { "test/ui/btn_test.dart", "flutter_test" }
)
eq(
  "locate java: src/main -> src/test con sufijo Test",
  loc("app/src/main/java/x/Foo.java", "java")[1],
  "app/src/test/java/x/FooTest.java"
)
eq("locate: lenguaje sin convención", loc("a.zig", "zig")[2]:find("no test convention", 1, true) ~= nil, true)

eq("is_test_file", {
  conv.is_test_file "/p/a_test.go",
  conv.is_test_file "/p/a.test.ts",
  conv.is_test_file "/p/a.spec.tsx",
  conv.is_test_file "/p/test_a.py",
  conv.is_test_file "/p/a_spec.lua",
  conv.is_test_file "/p/src/test/java/FooTest.java",
  conv.is_test_file "/p/a.go",
  conv.is_test_file "/p/testing.go",
}, { true, true, true, true, true, true, false, false })

local go_cmd = conv.command(proj .. "/pkg/store_test.go", "go", "TestX")
eq(
  "command go: paquete de la carpeta y la prueba exacta",
  go_cmd.cmd,
  { "go", "test", "./pkg", "-count=1", "-run", "^TestX$" }
)
eq(
  "command ts: vitest con -t",
  conv.command(proj .. "/src/a.test.ts", "typescript", "adds").cmd,
  { "npx", "--no-install", "vitest", "run", "src/a.test.ts", "-t", "adds" }
)
eq("command python: pytest -k", conv.command(proj .. "/pkg/test_a.py", "python", "test_a").cmd[3], "pytest")
eq(
  "command: lenguaje sin runner conocido",
  select(2, conv.command(proj .. "/a.lua", "lua", nil)):find("don't know how", 1, true) ~= nil,
  true
)

eq("run.clean: sin colores ni ruido de lo que pasa, con tope", {
  run.clean "\27[31mFAIL\27[0m x\n=== RUN T\n--- PASS: T\nok  pkg 0.1s\n\n",
  #run.clean(("boom line\n"):rep(1000)) <= 2600,
}, { "FAIL x", true })

-- ── proyecto Go temporal ─────────────────────────────────────────────────────
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function write(name, lines)
  vim.fn.writefile(lines, dir .. "/" .. name)
end
write("go.mod", { "module example.com/p", "", "go 1.21" })
write("store.go", {
  "package p", -- 1
  "", -- 2
  'import "errors"', -- 3
  "", -- 4
  'var ErrEmpty = errors.New("empty")', -- 5
  "", -- 6
  "type Note struct{ Title string }", -- 7
  "", -- 8
  "type Repo interface {", -- 9
  "\tGet(id int) (*Note, error)", -- 10
  "\tSave(n *Note) error", -- 11
  "}", -- 12
  "", -- 13
  "func Rename(r Repo, id int, title string) error {", -- 14
  "\tn, err := r.Get(id)", -- 15
  "\tif err != nil {", -- 16
  "\t\treturn err", -- 17
  "\t}", -- 18
  '\tif title == "" {', -- 19
  "\t\treturn ErrEmpty", -- 20
  "\t}", -- 21
  "\tn.Title = title", -- 22
  "\treturn r.Save(n)", -- 23
  "}", -- 24
  "", -- 25
  "func Tiny() int { return 1 }", -- 26
  "", -- 27
  "func Helper(a, b int) int {", -- 28
  "\tif a > b {", -- 29
  "\t\treturn a", -- 30
  "\t}", -- 31
  "\treturn b", -- 32
  "}", -- 33
})
write("query.go", {
  "package p", -- 1
  "", -- 2
  'import "database/sql"', -- 3
  "", -- 4
  "func Find(db *sql.DB, name string) error {", -- 5
  '\trows, err := db.Query("SELECT * FROM t WHERE n=\'" + name + "\'")', -- 6
  "\tif err != nil {", -- 7
  "\t\treturn err", -- 8
  "\t}", -- 9
  "\tdefer rows.Close()", -- 10
  "\tfor rows.Next() {", -- 11
  "\t}", -- 12
  "\treturn nil", -- 13
  "}", -- 14
})
vim.cmd.cd(dir)
vim.fn.system { "git", "-C", dir, "init", "-q" }
vim.fn.system { "git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A" }
vim.fn.system {
  "git",
  "-C",
  dir,
  "-c",
  "user.email=t@t",
  "-c",
  "user.name=t",
  "-c",
  "commit.gpgsign=false",
  "commit",
  "-qm",
  "base",
}

-- backend falso + estado en memoria + entrada en línea sin ventana
local agent_state = require "agent.state"
local real_get, real_set = agent_state.get, agent_state.set
local store = { backend = "fakeagent" }
agent_state.get = function(k)
  return store[k]
end
agent_state.set = function(k, v)
  store[k] = v
end
require("agent.runs.store").use(vim.fn.tempname() .. ".jsonl")
require("agent.persist").use(vim.fn.tempname() .. ".json")
local FAKE = { text = "", calls = 0 }
require("agent.backends").register("fakeagent", {
  name = "fakeagent",
  label = "Fake",
  available = function()
    return true
  end,
  models = function(cb)
    cb {}
  end,
  build = function(req)
    FAKE.req, FAKE.calls = req, FAKE.calls + 1
    return { cmd = { "printf", "%s", FAKE.text }, cwd = "/tmp" }
  end,
  parser = function()
    local buf = {}
    return {
      feed = function(chunk)
        buf[#buf + 1] = chunk
        return chunk
      end,
      finish = function(code)
        if code ~= 0 then
          return { ok = false, err = "boom" }
        end
        return { ok = true, text = table.concat(buf), usage = { tokens_in = 100, tokens_out = 20, cost = 0.0004 } }
      end,
    }
  end,
})
local ui_prompt = require "agent.ui.prompt"
ui_prompt.ask = function(_, _, _, cb)
  cb ""
end
local notes = {}
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
local function last_note()
  return notes[#notes] or ""
end

local function open(name)
  vim.cmd("silent edit " .. dir .. "/" .. name)
  vim.bo.filetype = "go"
  return vim.api.nvim_get_current_buf()
end
local function at(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end
local function idle()
  return wait(function()
    return #require("agent.jobs").running() == 0
  end)
end

local tests = require "agent.tests"
local replace = require "agent.output.replace"

-- ── destino: el final del archivo de pruebas ─────────────────────────────────
local src = open "store.go"
at(14)
local subject = require("agent.context.target").resolve(src, "function")
local tgt = dest.retarget(subject)
eq(
  "destino: archivo nuevo, una línea vacía como objetivo",
  { tgt.kind, tgt.path, tgt.lines, tgt.first, tgt.last },
  { "test-file-end", "store_test.go", { "" }, 1, 1 }
)
eq("destino: el código bajo prueba guarda su info de pruebas", subject.tests.exists, false)
eq("merge: archivo vacío = el código tal cual", dest.merge({ "package p" }, tgt), { "package p" })
eq(
  "merge: archivo con contenido = lo que había + línea en blanco + lo nuevo",
  dest.merge({ "func B() {}" }, { lines = { "}" } }),
  { "}", "", "func B() {}" }
)
eq("merge: sin código nuevo no cambia nada", dest.merge({}, { lines = { "}" } }), { "}" })
eq(
  "check: función pequeña no merece prueba",
  dest.check({ kind = "function", buf = src, lines = { "func Tiny() int { return 1 }" } }):find("too small", 1, true)
    ~= nil,
  true
)
at(26)
vim.cmd "bwipeout! store_test.go"

-- ── write: archivo nuevo, flujo entero ───────────────────────────────────────
FAKE.text =
  '```go\npackage p\n\nimport "testing"\n\nfunc TestRename(t *testing.T) {}\n```\nneeds-import: errors\nnote: assumed a fake Repo'
src = open "store.go"
at(14)
tests.run "write"
eq(
  "write: abre el archivo de pruebas a un lado con la propuesta",
  wait(function()
    return vim.api.nvim_buf_get_name(0):match "store_test%.go$" ~= nil
  end),
  true
)
local prompt = FAKE.req.prompt
eq("write: el prompt lleva testing, subject y el objetivo es el final del archivo de pruebas", {
  prompt:find("<testing>\ntest file: store_test.go (NEW", 1, true) ~= nil,
  prompt:find("<subject>", 1, true) ~= nil and prompt:find("func Rename(r Repo", 1, true) ~= nil,
  prompt:find('<target lines="1-1" kind="test-file-end"', 1, true) ~= nil,
  prompt:find("<testfile>", 1, true) == nil, -- archivo nuevo: no hay nada que resumir
}, { true, true, true, true })
eq(
  "write: el sistema pide SOLO lo nuevo",
  FAKE.req.system:find("output ONLY new test code to append", 1, true) ~= nil,
  true
)
eq(
  "write: el spinner/propuesta es del destino y NO crea el archivo todavía",
  vim.uv.fs_stat(dir .. "/store_test.go"),
  nil
)
replace.accept()
eq(
  "write: aceptar pone el código en el archivo de pruebas",
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  { "package p", "", 'import "testing"', "", "func TestRename(t *testing.T) {}" }
)
vim.cmd "silent write" -- el directorio ya existe; si no existiera, BufWritePre lo crea
eq("write: guardar crea el archivo", vim.uv.fs_stat(dir .. "/store_test.go") ~= nil, true)
vim.cmd "close"

-- ── write: archivo existente, solo lo que falta ──────────────────────────────
write("store_test.go", {
  "package p",
  "",
  'import "testing"',
  "",
  "func TestRenameOK(t *testing.T) {",
  '\tif err := Rename(nil, 1, "x"); err == nil {',
  '\t\tt.Log("Rename called")',
  "\t}",
  "}",
  "",
  "func TestOther(t *testing.T) {",
  "\tt.Log(1)",
  "\tt.Log(2)",
  "}",
})
vim.cmd "bwipeout! store_test.go"
FAKE.text = "```go\nfunc TestRenameEmpty(t *testing.T) {\n}\n```"
src = open "store.go"
at(14)
tests.run "write"
wait(function()
  return vim.api.nvim_buf_get_name(0):match "store_test%.go$" ~= nil
end)
prompt = FAKE.req.prompt
eq("write existente: cabecera, nombres, y lo que ya cubre la función (añadir solo lo que falta)", {
  prompt:find("exists: append to it", 1, true) ~= nil,
  prompt:find("-- existing tests: TestRenameOK, TestOther", 1, true) ~= nil,
  prompt:find("already cover Rename (add only what is missing)", 1, true) ~= nil,
  prompt:find("func TestRenameOK", 1, true) ~= nil,
  prompt:find('<target lines="14-14"', 1, true) ~= nil,
}, { true, true, true, true, true })
eq("write existente: el prompt no lleva el archivo de pruebas entero", prompt:find("func TestOther", 1, true), nil)
replace.accept()
local tl = vim.api.nvim_buf_get_lines(0, 0, -1, false)
eq(
  "write existente: se añade al final, separado por una línea en blanco",
  { tl[#tl - 4], tl[#tl - 3], tl[#tl - 2], tl[#tl - 1], tl[#tl] },
  { "\tt.Log(2)", "}", "", "func TestRenameEmpty(t *testing.T) {", "}" }
)
vim.cmd "silent write"
vim.cmd "close"

-- ── write sobre un archivo de pruebas, y sin convención ──────────────────────
vim.cmd("silent edit " .. dir .. "/store_test.go")
at(5)
local calls = FAKE.calls
tests.run "write"
eq(
  "write: en un archivo de pruebas avisa y no gasta",
  { last_note():find("already a test file", 1, true) ~= nil, FAKE.calls },
  { true, calls }
)

-- ── mock ─────────────────────────────────────────────────────────────────────
FAKE.text = "```go\ntype fakeRepo struct{}\n```"
src = open "store.go"
at(10)
tests.run "mock"
wait(function()
  return vim.api.nvim_buf_get_name(0):match "store_test%.go$" ~= nil
end)
eq("mock: el sujeto es la interfaz (sus métodos viajan) y va con el modelo ligero", {
  FAKE.req.prompt:find("Get(id int) (*Note, error)", 1, true) ~= nil,
  FAKE.req.system:find("test double", 1, true) ~= nil,
  require("agent.selection").tier_of(require("agent.tests.actions").get "mock"),
}, { true, true, "light" })
replace.reject()
vim.cmd "close"

-- ── fix: corre la prueba y solo gasta si falla ───────────────────────────────
if vim.fn.executable "go" == 1 then
  write("store_test.go", {
    "package p",
    "",
    'import "testing"',
    "",
    "func TestPasses(t *testing.T) {",
    "\tif Helper(1, 2) != 2 {",
    '\t\tt.Fatal("no")',
    "\t}",
    "}",
    "",
    "func TestBroken(t *testing.T) {",
    "\tif Helper(1, 2) != 99 {",
    '\t\tt.Fatal("helper returned the wrong value")',
    "\t}",
    "}",
  })
  vim.cmd "bwipeout! store_test.go"
  vim.cmd("silent edit " .. dir .. "/store_test.go")
  at(6)
  calls = FAKE.calls
  tests.run "fix"
  eq("fix: una prueba que pasa no llama al modelo (0 tokens)", wait(function()
    return last_note():find("already passes", 1, true) ~= nil
  end) and FAKE.calls == calls, true)
  FAKE.text =
    '```go\nfunc TestBroken(t *testing.T) {\n\tif Helper(1, 2) != 2 {\n\t\tt.Fatal("helper returned the wrong value")\n\t}\n}\n```'
  at(12)
  tests.run "fix"
  eq(
    "fix: una prueba que falla manda su salida real y propone el arreglo",
    wait(function()
      return FAKE.calls == calls + 1 and #require("agent.jobs").running() == 0
    end)
      and FAKE.req.prompt:find("<test_output>", 1, true) ~= nil
      and FAKE.req.prompt:find("helper returned the wrong value", 1, true) ~= nil
      and FAKE.req.prompt:find("$ go test ./ -count=1 -run ^TestBroken$", 1, true) ~= nil,
    true
  )
  replace.reject()
  vim.cmd("silent edit! " .. dir .. "/store.go")
  at(14)
  calls = FAKE.calls
  tests.run "fix"
  eq(
    "fix: fuera de un archivo de pruebas avisa y no gasta",
    { last_note():find("put the cursor in a test function", 1, true) ~= nil, FAKE.calls },
    { true, calls }
  )
else
  print "skip go no instalado: se omite la prueba de `fix`"
end

-- ── huecos (local) ───────────────────────────────────────────────────────────
src = open "store.go"
tests.gaps()
local qf = vim.fn.getqflist { items = 1, title = 1 }
local names = vim.tbl_map(function(i)
  return i.text:match "^(%w+)"
end, qf.items)
table.sort(names)
eq(
  "huecos: funciones públicas sin ninguna prueba que las nombre",
  { qf.title, names },
  { "Untested functions (3 of 4)", { "Find", "Rename", "Tiny" } }
)
vim.cmd "cclose"

-- ── lentes ───────────────────────────────────────────────────────────────────
local lenses = require "agent.lenses.actions"
local list = lenses.list()
eq("lentes: 5, teclas distintas, salen como diagnósticos con su origen", {
  #list,
  #vim.fn.uniq(vim.fn.sort(vim.tbl_map(function(a)
    return a.key
  end, list))),
  vim.tbl_map(function(a)
    return a.output .. ":" .. a.source
  end, list),
}, { 5, 5, { "findings:security", "findings:performance", "findings:concurrency", "findings:errors", "findings:api" } })
eq(
  "lentes: seguridad y concurrencia usan el modelo principal; el resto, el ligero",
  vim.tbl_map(function(a)
    return require("agent.selection").tier_of(a)
  end, list),
  { "main", "light", "main", "light", "light" }
)
eq("lentes: nombre de acción lens_<x> (para reasignar el tier)", lenses.get("security").name, "lens_security")

src = open "store.go"
at(14)
local rename = require("agent.context.target").resolve(src, "function")
eq(
  "puerta: seguridad no llama al modelo si no hay nada de seguridad",
  lenses.get("security").check(rename):find("skipped (0 tokens)", 1, true) ~= nil,
  true
)
eq(
  "puerta: concurrencia tampoco sin hilos/locks",
  lenses.get("concurrency").check(rename):find("skipped", 1, true) ~= nil,
  true
)
eq("puerta: errores sí pasa (hay err)", lenses.get("errors").check(rename), nil)
local query_buf = open "query.go"
at(5)
local find = require("agent.context.target").resolve(query_buf, "function")
eq("puerta: seguridad pasa con SQL", lenses.get("security").check(find), nil)
eq(
  "api: sin cambios sin commitear no hay contra qué comparar",
  lenses.get("api").check(find):find("no uncommitted changes", 1, true) ~= nil,
  true
)

-- flujo entero: dos lentes conviven y repetir una solo reemplaza lo suyo
local fns = vim.api.nvim_create_namespace "agent.findings"
FAKE.text = "L6|error|SQL built by concatenating name: use a placeholder"
at(5)
require("agent.lenses").run "security"
idle()
FAKE.text = "L11|warn|loop without a limit"
require("agent.lenses").run "performance"
idle()
local function srcs()
  local out = vim.tbl_map(function(d)
    return d.source
  end, vim.diagnostic.get(query_buf, { namespace = fns }))
  table.sort(out)
  return out
end
eq("lentes: dos lentes conviven en la misma función", srcs(), { "performance", "security" })
eq("lentes: el prompt lleva el foco y el código numerado", {
  FAKE.req.system:find("Report ONLY performance problems", 1, true) ~= nil,
  FAKE.req.prompt:find("6: ", 1, true) ~= nil,
}, { true, true })
FAKE.text = "L6|error|string concatenation in SQL again"
require("agent.lenses").run "security"
idle()
local d2 = vim.diagnostic.get(query_buf, { namespace = fns })
table.sort(d2, function(a, b)
  return a.source < b.source
end)
eq(
  "lentes: repetir una solo reemplaza sus propios hallazgos",
  { #d2, d2[1].source, d2[2].source, d2[2].message },
  { 2, "performance", "security", "string concatenation in SQL again" }
)

-- api: con cambios sin commitear sí corre, y el diff viaja
vim.fn.writefile({
  "package p",
  "",
  'import "database/sql"',
  "",
  "func Find(db *sql.DB, name string, limit int) error {",
  '\trows, err := db.Query("SELECT * FROM t")',
  "\tif err != nil {",
  "\t\treturn err",
  "\t}",
  "\tdefer rows.Close()",
  "\tfor rows.Next() {",
  "\t}",
  "\treturn nil",
  "}",
}, dir .. "/query.go")
vim.cmd "silent edit!"
at(5)
FAKE.text = "L5|warn|new required parameter breaks every caller"
calls = FAKE.calls
require("agent.lenses").run "api"
idle()
eq("api: con cambios corre y manda el diff (-/+) de la función", {
  FAKE.calls == calls + 1,
  FAKE.req.prompt:find("<changes>", 1, true) ~= nil,
  FAKE.req.prompt:find("-func Find(db *sql.DB, name string) error {", 1, true) ~= nil,
  FAKE.req.prompt:find("+func Find(db *sql.DB, name string, limit int) error {", 1, true) ~= nil,
}, { true, true, true, true })

-- puerta: una lente que no aplica no cuesta nada
calls = FAKE.calls
at(14 - 9) -- dentro de Find
vim.api.nvim_set_current_buf(src)
at(14)
require("agent.lenses").run "concurrency"
eq("puerta: la lente que no aplica no llama al modelo", FAKE.calls, calls)

agent_state.get, agent_state.set = real_get, real_set
require("agent.runs.store").use(nil)
require("agent.persist").use(nil)
vim.cmd.cd "/"
vim.fn.delete(dir, "rf")
vim.fn.delete(proj, "rf")
print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
