-- Pruebas del agente (parsers, protocolo, objetivo). Sin red ni tokens.
-- Se ejecutan con scripts/test-agent.sh dentro de nvim headless con la config real.
local fails = 0
-- headless `print` no termina la línea: se escribe a stdout a mano
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
local protocol = require "agent.protocol"

-- extract_code
local code, needs = protocol.extract_code "```go\nfunc A() {\n}\n```\nneeds-import: strings, fmt"
eq("extract_code básico", code, { "func A() {", "}" })
eq("needs-import", needs, "strings, fmt")
code, needs = protocol.extract_code "Aquí va:\n```lua\nlocal x = 1\n```\nneeds-import: none"
eq("ignora prosa previa y 'none'", { code, needs }, { { "local x = 1" }, nil })
code = protocol.extract_code("```md\n# t\n```lua\nx=1\n```\ntexto\n```", { "```lua", "x=1", "```" })
eq("valla anidada (objetivo markdown): cierra en la ÚLTIMA", code, { "# t", "```lua", "x=1", "```", "texto" })
local c, _, err = protocol.extract_code "sin bloque"
eq("sin bloque → error", { c, err ~= nil }, { nil, true })
c, _, err = protocol.extract_code "```go\nfunc A() {"
eq("bloque sin cerrar → error", { c, err ~= nil }, { nil, true })
eq("bloque vacío = lista vacía", protocol.extract_code "```\n```", {})

-- varios bloques (borrador + corregido): gana el último que empieza como el objetivo
local target_fn = { "/// doc", "fn f() {", "}" }
local draft_and_fix =
  "```rust\n/// doc\nfn f() { 1 }\n```\n\nWait, that is wrong. Corrected:\n\n```rust\n/// doc\nfn f() { 2 }\n```\nneeds-import: none"
local picked, _, _, n_blocks = protocol.extract_code(draft_and_fix, target_fn)
eq(
  "varios bloques: elige el último que empieza como el objetivo",
  { picked, n_blocks },
  { { "/// doc", "fn f() { 2 }" }, 2 }
)
local code_and_example = "```rust\n/// doc\nfn f() { 1 }\n```\nExample:\n```rust\nlet x = f();\n```"
eq(
  "varios bloques: un ejemplo posterior no gana",
  (protocol.extract_code(code_and_example, target_fn)),
  { "/// doc", "fn f() { 1 }" }
)
eq(
  "varios bloques: si ninguno coincide, el primero",
  (protocol.extract_code("```\nA\n```\n```\nB\n```", { "zzz" })),
  { "A" }
)
eq(
  "objetivo markdown (con vallas): primera a última",
  (protocol.extract_code("```md\n```go\nx\n```\n```", { "```go", "x", "```" })),
  { "```go", "x", "```" }
)
eq("bloque sin cerrar tras uno válido: se ignora", (protocol.extract_code("```a\nok\n```\n```b\nroto", nil)), { "ok" })

-- findings
local f = protocol.parse_findings "L12|warn|algo mal\nbasura\n  L3 | ERROR | otro  \nL9|raro|sev desconocida\nL1|info|"
eq("findings: 3 válidos (vacío y basura se ignoran)", #f, 3)
eq(
  "severidad",
  { f[1].severity, f[2].severity, f[3].severity },
  { vim.diagnostic.severity.WARN, vim.diagnostic.severity.ERROR, vim.diagnostic.severity.INFO }
)
eq("línea y mensaje", { f[2].line, f[2].message }, { 3, "otro" })
eq("is_ok", { protocol.is_ok " ok \n", protocol.is_ok "L1|warn|x" }, { true, false })

-- ndjson troceado
local nd = require "agent.backends.ndjson"
local got = {}
local feed = nd.new(function(o)
  got[#got + 1] = o.n
  return tostring(o.n)
end)
local out = (feed '{"n":1}\n{"n"' or "") .. (feed ':2}\n\n{"n":3}' or "") .. (feed "\n" or "")
eq("ndjson reensambla chunks cortados", { got, out }, { { 1, 2, 3 }, "123" })

-- claude parser
local claude = require "agent.backends.claude"
local p = claude.parser()
local d1 =
  p.feed '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Ho"}}}\n'
local d2 =
  p.feed '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"x"}}}\n{"type":"result","is_error":false,"result":"Hola","total_cost_usd":0.001,"duration_ms":900,"usage":{"input_tokens":2,"cache_creation_input_tokens":500,"cache_read_input_tokens":100,"output_tokens":7}}\n'
local r = p.finish(0, "")
eq("claude: delta de texto, no de thinking", { d1, d2 }, { "Ho", nil })
eq(
  "claude: resultado",
  { r.ok, r.text, r.usage.tokens_in, r.usage.tokens_out, r.usage.cost },
  { true, "Hola", 602, 7, 0.001 }
)
local pe = claude.parser()
pe.feed '{"type":"result","is_error":true,"result":"límite de uso alcanzado"}\n'
eq("claude: error del CLI", pe.finish(1, ""), { ok = false, err = "límite de uso alcanzado" })
eq(
  "claude: salida sin result y código≠0 usa stderr",
  claude.parser().finish(1, "boom\n"),
  { ok = false, err = "boom" }
)
local spec = claude.build { system = "SYS", prompt = "P", model = "haiku", effort = "low", action = "review" }
eq("claude: argv clave", {
  vim.tbl_contains(spec.cmd, "--tools"),
  spec.cmd[vim.fn.index(spec.cmd, "--setting-sources") + 2],
  spec.stdin,
  spec.cmd[vim.fn.index(spec.cmd, "--effort") + 2],
  vim.tbl_contains(spec.cmd, "--max-budget-usd"),
}, { true, "", "P", "low", true })
eq("claude: sin caché de prompts por defecto", spec.env, { DISABLE_PROMPT_CACHING = "1" })

-- opencode parser + build
local oc = require "agent.backends.opencode"
local q = oc.parser()
local e1 =
  q.feed '{"type":"step_start","part":{"type":"step-start"}}\n{"type":"text","part":{"id":"p1","type":"text","text":"Hel"}}\n'
local e2 =
  q.feed '{"type":"text","part":{"id":"p1","type":"text","text":"Hello"}}\n{"type":"step_finish","part":{"tokens":{"input":10,"output":5,"cache":{"read":3,"write":2}},"cost":0.002}}\n'
local qr = q.finish(0, "")
eq("opencode: emite solo lo nuevo de una parte que crece", { e1, e2 }, { "Hel", "lo" })
eq(
  "opencode: texto final y uso",
  { qr.ok, qr.text, qr.usage.tokens_in, qr.usage.tokens_out, qr.usage.cost },
  { true, "Hello", 15, 5, 0.002 }
)
local qe = oc.parser()
qe.feed '{"type":"error","error":{"name":"APIError","data":{"message":"Forbidden"}}}\n'
eq("opencode: error con mensaje", qe.finish(1, ""), { ok = false, err = "Forbidden" })
eq("opencode: sin texto ni error", oc.parser().finish(0, "").ok, false)
local ospec =
  oc.build { system = "SYS", prompt = "PROMPT", model = "opencode-go/x", action = "explain", effort = "high" }
local cfg = vim.json.decode(ospec.env.OPENCODE_CONFIG_CONTENT)
eq(
  "opencode: agente efímero sin herramientas",
  { cfg.agent["nvim-explain"].prompt, cfg.agent["nvim-explain"].tools.bash, cfg.agent["nvim-explain"].permission.edit },
  { "SYS", false, "deny" }
)
eq("opencode: argv", {
  ospec.cmd[vim.fn.index(ospec.cmd, "--agent") + 2],
  ospec.cmd[vim.fn.index(ospec.cmd, "--variant") + 2],
  ospec.cmd[#ospec.cmd],
  ospec.cmd[#ospec.cmd - 1],
}, { "nvim-explain", "high", "PROMPT", "--" })

-- diff y objetivo sin treesitter
local diff = require "agent.output.diff"
eq("diff: inserción al inicio", diff.hunks({ "a", "b" }, { "x", "a", "b" })[1].a_start, 0)
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "una nota", "sin parser", "", "otro párrafo" })
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local target = require("agent.context.target").resolve(buf, "function", nil)
eq("target sin parser = párrafo (líneas 1-2)", { target.kind, target.first, target.last }, { "lines", 1, 2 })
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "" })
eq(
  "target vacío → error",
  select(2, require("agent.context.target").resolve(buf, "function", nil)),
  "no code under the cursor"
)

-- modelos por tier. Hermético: con un estado vacío, no con el modelo que hayas elegido tú en <leader>am
local real_state_mod, real_selection = package.loaded["agent.state"], package.loaded["agent.selection"]
package.loaded["agent.state"] = {
  get = function()
    return nil
  end,
  set = function() end,
}
package.loaded["agent.selection"] = nil
local selection = require "agent.selection"
local actions = require "agent.actions"
if require("agent.backends").is_available "claude" and selection.current().backend == "claude" then
  local docs, implement = actions.get "docs", actions.get "implement"
  eq("tier: docs corre en el modelo ligero", selection.current(docs).model, "haiku")
  eq(
    "tier: implement corre en el principal",
    selection.current(implement).model,
    require("core.settings").agent.claude.model
  )
  eq("tier: el ligero no hereda el esfuerzo", selection.current(docs).effort, nil)
  local settings = require("core.settings").agent
  settings.tiers.review = "light"
  eq("tier: settings.agent.tiers reasigna una acción", selection.tier_of(actions.get "review"), "light")
  settings.tiers.review = nil
end
eq(
  "tier: explain y docs son ligeros por defecto",
  { selection.tier_of(actions.get "explain"), selection.tier_of(actions.get "docs") },
  { "light", "light" }
)
eq(
  "tier: implement/fix/refactor/review/ask son principales",
  vim.tbl_map(function(n)
    return selection.tier_of(actions.get(n))
  end, { "implement", "fix", "refactor", "review", "ask" }),
  { "main", "main", "main", "main", "main" }
)
package.loaded["agent.state"], package.loaded["agent.selection"] = real_state_mod, real_selection

-- la instrucción del usuario solo entra en las variantes opcionales; en las que ya piden texto va en su `task`
local prompt = require "agent.prompt"
local tgt = {
  buf = 0,
  path = "a.go",
  lang = "go",
  kind = "function",
  name = "main",
  first = 1,
  last = 2,
  lines = { "func main() {", "}" },
}
local _, plain = prompt.build(actions.get "implement", tgt, {}, nil)
local _, with = prompt.build(actions.get "implement", tgt, {}, "print the numbers 1 to 5")
eq("prompt: sin instrucción no hay bloque adicional", plain:find("Additional instruction", 1, true), nil)
eq(
  "prompt: con instrucción, va dentro de <task> y manda",
  { with:find("Additional instruction", 1, true) ~= nil, with:find("print the numbers 1 to 5", 1, true) ~= nil },
  { true, true }
)
local _, ask = prompt.build(actions.get "ask", tgt, {}, "why?")
eq("prompt: ask no duplica la instrucción", select(2, ask:gsub("why%?", "")), 1)
for _, n in ipairs { "implement", "docs", "fix" } do
  local a = actions.get(n)
  eq(
    "'" .. n .. "' pide instrucción opcional (Enter vacío corre igual)",
    { a.input ~= nil, a.input_optional },
    { true, true }
  )
end
for _, n in ipairs { "ask", "refactor" } do
  local a = actions.get(n)
  eq("'" .. n .. "' exige texto", { a.input ~= nil, a.input_optional }, { true, nil })
end
eq(
  "review y explain corren al instante (sin campo)",
  { actions.get("review").input, actions.get("explain").input },
  { nil, nil }
)
local keys, seen = {}, true
for _, a in ipairs(actions.list()) do
  seen = seen and not keys[a.key]
  keys[a.key] = true
end
eq("las teclas de las acciones no se repiten", seen, true)
eq("handoff solo se ofrece dentro de Herdr", actions.get("handoff").enabled ~= nil, true)

-- recuerdo de instrucciones (con un estado falso: no toca el agent.json real)
local fake_state = { data = {} }
function fake_state.get(key)
  return fake_state.data[key]
end
function fake_state.set(key, value)
  fake_state.data[key] = value
end
local real_state = package.loaded["agent.state"]
package.loaded["agent.state"], package.loaded["agent.recall"] = fake_state, nil
local history = require "agent.recall"
history.push("implement", "a")
history.push("implement", "b")
history.push("implement", "a")
eq("historial: lo más reciente primero y sin repetidos", history.list "implement", { "a", "b" })
eq("historial: cada acción tiene el suyo", history.list "docs", {})
for i = 1, 40 do
  history.push("x", "t" .. i)
end
eq("historial: tope de 30", { #history.list "x", history.list("x")[1] }, { 30, "t40" })
package.loaded["agent.state"], package.loaded["agent.recall"] = real_state, nil

-- historial de ejecuciones: almacén (JSONL), plegado de eventos, compactación, informe y detalle
local store = require "agent.runs.store"
local report = require "agent.runs.report"
local detail = require "agent.runs.detail"
local rfmt = require "agent.runs.format"
local tmp = vim.fn.tempname() .. ".jsonl"
store.use(tmp)
local function run(id, ts, extra)
  return vim.tbl_deep_extend("force", {
    t = "run",
    id = id,
    ts = ts,
    action = "implement",
    output = "replace",
    backend = "claude",
    model = "sonnet",
    status = "done",
    ms = 3000,
    file = "a.go",
    first = 5,
    last = 12,
    kind = "function",
    name = "Total",
    cwd = "/p",
    usage = { tokens_in = 1300, tokens_out = 100, cache_read = 0, cache_write = 0, cost = 0.004 },
    context = { { name = "outline", chars = 400 } },
    chars = { system = 1100, message = 700, target = 150, context = 400 },
    system = "SYS ```fence``` inside",
    prompt = "MSG",
    response = "RESP",
  }, extra or {})
end
local now = os.time()
store.append(run("r1", now - 100))
store.append { t = "event", id = "r1", ts = now - 90, event = "accepted" }
store.append(run("r2", now - 80, { usage = { cost = 0.006 } }))
store.append { t = "event", id = "r2", ts = now - 70, event = "rejected" }
store.append(
  run("r3", now - 60, { action = "review", output = "findings", model = "haiku", usage = { cost = 0.0003 } })
)
store.append { t = "event", id = "r3", ts = now - 50, event = "findings", detail = 3 }
store.append(run("r4", now - 40, { status = "error", error = "boom", usage = {} }))
store.append(run("r5", now - 30))
store.append { t = "event", id = "orphan", ts = now, event = "accepted" } -- evento sin ejecución: se ignora
vim.fn.writefile({ "{not json" }, tmp, "a") -- línea corrupta: se ignora
local runs = store.read()
local by = {}
for _, r in ipairs(runs) do
  by[r.id] = r
end
eq("historial: 5 ejecuciones, la más reciente primero", { #runs, runs[1].id }, { 5, "r5" })
eq(
  "historial: resultados plegados",
  { by.r1.outcome, by.r2.outcome, by.r3.outcome, by.r3.detail, by.r4.outcome, by.r5.outcome },
  { "accepted", "rejected", "findings", 3, "error", "pending" }
)
local lines = report.build(runs, now)
local text = table.concat(lines, "\n")
eq("informe: total acumulado", text:find("All time | 5 |", 1, true) ~= nil, true)
eq(
  "informe: coste por cambio aplicado (1 aceptada de 3 propuestas)",
  text:find("1 of 3 proposals accepted", 1, true) ~= nil,
  true
)
eq("informe: lo gastado en propuestas sin aplicar", text:find("Spent on proposals not applied", 1, true) ~= nil, true)
eq("informe: caché 0%", text:find "0%% of input tokens were cache reads" ~= nil, true)
eq("informe: vacío no falla", report.build({}, now)[3], "_No runs recorded yet._")
eq("titular del selector", report.headline(runs), "5 runs · $0.0183")
local d = table.concat(detail.build(by.r1), "\n")
eq(
  "detalle: muestra prompt, respuesta y coste",
  { d:find("SYS", 1, true) ~= nil, d:find("RESP", 1, true) ~= nil, d:find("$0.0040", 1, true) ~= nil },
  { true, true, true }
)
local whole = detail.text(by.r1)
eq("copiar todo: metadatos, resultado, eventos, instrucción, respuesta, sistema y mensaje", {
  whole:find("# implement · claude/sonnet", 1, true) ~= nil,
  whole:find("accepted @", 1, true) ~= nil,
  whole:find("## Your instruction", 1, true) ~= nil,
  whole:find("RESP", 1, true) ~= nil,
  whole:find("SYS", 1, true) ~= nil,
  whole:find("MSG", 1, true) ~= nil,
  whole:sub(-1),
}, { true, true, true, true, true, true, "\n" })
eq("detalle: una valla dentro del texto no rompe el bloque", d:find("````text", 1, true) ~= nil, true)
eq(
  "formato: dinero y tokens",
  { rfmt.money(0.00123), rfmt.money(2.5), rfmt.tokens(1234), rfmt.tokens(87) },
  { "$0.0012", "$2.50", "1.2k", "87" }
)
require("core.settings").agent.history.max_entries = 2
store.compact()
eq(
  "compactar: 5 > 2×1.5 → quedan las 2 más recientes con sus eventos",
  { #store.read(), store.read()[1].id },
  { 2, "r5" }
)
require("core.settings").agent.history.max_entries = 1000
os.remove(tmp)
store.use(nil)

-- tipos que usa el objetivo (treesitter, sin LSP): el modelo no debe adivinar los campos
local target_mod = require "agent.context.target"
local types = require "agent.context.providers.types"
local outline = require "agent.context.providers.outline"
local diagnostics = require "agent.context.providers.diagnostics"
local function with_buffer(ft, lines, row)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].filetype = ft
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  return b
end
local function collect(provider, buf, ctx)
  local out
  local tgt = assert(target_mod.resolve(buf, "function", nil))
  provider.collect(tgt, function(text)
    out = text or ""
  end, ctx)
  vim.wait(300, function()
    return out ~= nil
  end)
  return out, tgt
end
local function has_parser(lang)
  return pcall(vim.treesitter.language.add, lang)
end

if has_parser "go" then
  local b = with_buffer("go", {
    "package domain",
    "",
    "type Note struct {",
    "\tID      string",
    "\tDone    bool",
    "\tUpdated time.Time",
    "\tTags    []Tag",
    "}",
    "",
    "type Tag struct{ Name string }",
    "",
    "type Unused struct{ X int }",
    "",
    "func (n *Note) SetDone(done bool) {",
    "}",
  }, 14)
  local text, tgt = collect(types, b)
  eq(
    "tipos Go: receptor con sus campos",
    { text:find("Done    bool", 1, true) ~= nil, text:find("Updated time.Time", 1, true) ~= nil },
    { true, true }
  )
  eq("tipos Go: sigue el tipo de un campo (Tags []Tag)", text:find("type Tag struct", 1, true) ~= nil, true)
  eq(
    "tipos Go: no mete tipos que nadie usa ni el propio objetivo",
    { text:find("Unused", 1, true), text:find("SetDone", 1, true) },
    { nil, nil }
  )
  local o = collect(outline, b, { names = { "outline", "types" } })
  eq("outline: con <types> no repite las definiciones de tipo", o:find("type Note struct", 1, true), nil)
  local o2 = collect(outline, b, { names = { "outline" } })
  eq("outline: sin <types> sí las lista", o2:find("type Note struct", 1, true) ~= nil, true)
  -- diagnósticos: cada mensaje lleva su línea de código (el objetivo no va numerado)
  local ns = vim.api.nvim_create_namespace "test-agent-diag"
  vim.diagnostic.set(ns, b, { { lnum = 13, col = 0, message = "boom", severity = 1, source = "gopls" } })
  local d = collect(diagnostics, b)
  eq("diagnóstico con su línea de código", d, "L14 ERROR: boom [gopls] | func (n *Note) SetDone(done bool) {")
  vim.diagnostic.reset(ns, b)
end

if has_parser "python" then
  local b = with_buffer(
    "python",
    { "class Note:", "    id: str", "    done: bool", "", "    def set_done(self, done):", "        pass" },
    5
  )
  local text = collect(types, b)
  eq(
    "tipos Python: la clase del método, sin el propio método",
    { text:find("id: str", 1, true) ~= nil, text:find("…", 1, true) ~= nil, text:find("pass", 1, true) },
    { true, true, nil }
  )
end

if has_parser "rust" then
  local b = with_buffer("rust", {
    "pub struct Note { pub id: String, pub done: bool }",
    "impl Note {",
    "    pub fn set_done(&mut self, d: bool) {",
    "    }",
    "}",
  }, 3)
  local text = collect(types, b)
  eq(
    "tipos Rust: un método de `impl Note` trae `struct Note`",
    { text:find("pub struct Note", 1, true) ~= nil, text:find("impl Note", 1, true) },
    { true, nil }
  )
end

if has_parser "typescript" then
  local b = with_buffer(
    "typescript",
    { "export interface Note { id: string; done: boolean }", "", "export function finish(n: Note): void {", "}" },
    3
  )
  local text = collect(types, b)
  eq("tipos TypeScript: interfaz del parámetro", text:find("interface Note", 1, true) ~= nil, true)
end

if has_parser "java" then
  local b = with_buffer(
    "java",
    { "enum Kind { A, B }", "class Note {", "  private boolean done;", "  void setKind(Kind k) {", "  }", "}" },
    4
  )
  local text = collect(types, b)
  eq(
    "tipos Java: enum (que la query no captura) y la clase del método",
    { text:find("enum Kind", 1, true) ~= nil, text:find("private boolean done", 1, true) ~= nil },
    { true, true }
  )
end

-- `note:` y `needs-import:` tras el bloque
local _, needs2, _, _, note2 =
  protocol.extract_code("```go\nx\n```\nneeds-import: strings\nnote: Note has no Done field; assumed one", { "x" })
eq("note: se lee junto a needs-import", { needs2, note2 }, { "strings", "Note has no Done field; assumed one" })
eq("note: none se ignora", select(5, protocol.extract_code("```go\nx\n```\nnote: none", { "x" })), nil)

-- política de contexto coherente: cada acción pide lo que necesita, por prioridad
local function ctx_of(n)
  return actions.get(n).context
end
eq(
  "contexto: fix prioriza diagnostics, luego findings y contracts",
  { ctx_of("fix")[2], ctx_of("fix")[3], ctx_of("fix")[4] },
  { "diagnostics", "findings", "contracts" }
)
eq(
  "contexto: docs y explain reciben types",
  { vim.tbl_contains(ctx_of "docs", "types"), vim.tbl_contains(ctx_of "explain", "types") },
  { true, true }
)
eq(
  "contexto: docs no paga outline ni callees",
  { vim.tbl_contains(ctx_of "docs", "outline"), vim.tbl_contains(ctx_of "docs", "callees") },
  { false, false }
)
for _, n in ipairs { "implement", "review", "fix", "refactor", "ask", "explain", "docs" } do
  eq("contexto: '" .. n .. "' incluye types", vim.tbl_contains(ctx_of(n), "types"), true)
end

-- regresión: un literal `&Order{...}` no es otra definición de `Order` (la query de Go lo captura como class.outer)
if has_parser "go" then
  local decls = require("agent.context.scopes").type_declarations(
    'package p\n\ntype Order struct{ ID string }\n\nfunc New() *Order {\n\treturn &Order{ID: "x"}\n}\n',
    "go"
  )
  eq(
    "tipos: un literal de struct no cuenta como definición",
    { #decls, decls[1] and decls[1].name, decls[1] and decls[1].first },
    { 1, "Order", 3 }
  )
end

-- constantes asociadas a un tipo (el "enum" de Go) viajan con él
if has_parser "go" then
  local b = with_buffer("go", {
    "package order",
    "",
    "type Status string",
    "",
    "const (",
    '\tPending   Status = "pending"',
    '\tConfirmed Status = "confirmed"',
    ")",
    "",
    "type Order struct {",
    "\tStatus Status",
    "}",
    "",
    "func (o *Order) Confirm() error {",
    "}",
  }, 14)
  local text = collect(types, b)
  eq(
    "tipos: el tipo Status trae sus constantes (Pending, Confirmed)",
    { text:find("type Status string", 1, true) ~= nil, text:find('Confirmed Status = "confirmed"', 1, true) ~= nil },
    { true, true }
  )
end

-- DDD: imports, capas, reglas, agregados, cableado, nomenclatura y la sección <ddd> (proyecto Go sintético)
local ddd_imports = require "agent.ddd.imports"
local ddd_layers = require "agent.ddd.layers"
local ddd_index = require "agent.ddd.index"
local ddd_rules = require "agent.ddd.rules"
local ddd_naming = require "agent.ddd.naming"
local ddd_profile = require "agent.ddd.profile"

local function specs(list)
  return vim.tbl_map(function(i)
    return i.spec
  end, list)
end
eq(
  "imports Go (bloque y alias)",
  specs(ddd_imports.extract({ "import (", '\t"fmt"', '\tdb "x/infrastructure/db"', ")" }, "go")),
  { "fmt", "x/infrastructure/db" }
)
eq(
  "imports TS",
  specs(ddd_imports.extract({ "import { A } from '../../infrastructure/db'", "const x = require('express')" }, "ts")),
  { "../../infrastructure/db", "express" }
)
eq(
  "imports Python",
  specs(ddd_imports.extract({ "from app.infrastructure.db import Session", "import os" }, "py")),
  { "app.infrastructure.db", "os" }
)
eq(
  "imports Java",
  specs(ddd_imports.extract({ "import com.acme.infrastructure.Db;", "import static org.x.Y.z;" }, "java")),
  { "org.x.Y.z", "com.acme.infrastructure.Db" }
)
eq(
  "imports Rust",
  specs(ddd_imports.extract({ "use crate::infrastructure::db;" }, "rs")),
  { "crate::infrastructure::db" }
)
eq("framework: reconoce el paquete y no confunde subcadenas", {
  ddd_imports.framework("database/sql", "go"),
  ddd_imports.framework("example.com/notes/sqlutil", "go"),
  ddd_imports.framework("express", "ts"),
  ddd_imports.framework("./expressions", "ts"),
}, { "database/sql", nil, "express", nil })
eq("capas por directorio / import", {
  ddd_layers.of "internal/domain/order/order.go",
  ddd_layers.of "x/Infrastructure/db",
  ddd_layers.of "src/api/routes.ts",
  ddd_layers.of "util/strings.go",
}, { "domain", "infrastructure", "interface", nil })
eq("la regla de dependencia apunta hacia dentro", {
  ddd_layers.ALLOWED.domain.infrastructure,
  ddd_layers.ALLOWED.infrastructure.domain,
  ddd_layers.ALLOWED.application.interface,
}, { nil, true, nil })
eq("raíz de composición y tests", {
  ddd_layers.is_composition_root "cmd/api/main.go",
  ddd_layers.is_composition_root "internal/domain/order.go",
  ddd_layers.is_test "internal/order_test.go",
  ddd_layers.is_test "src/order.spec.ts",
}, { true, false, true, true })

local proj = vim.fn.tempname()
local function write(rel, lines)
  local dir = vim.fn.fnamemodify(rel, ":h")
  vim.fn.mkdir(dir == "." and proj or (proj .. "/" .. dir), "p")
  vim.fn.writefile(lines, proj .. "/" .. rel)
end
write("go.mod", { "module example.com/shop", "go 1.22" })
write("domain/order/order.go", {
  "package order",
  "",
  "import (",
  '\t"database/sql"',
  '\t"example.com/shop/infrastructure/postgres"',
  ")",
  "",
  "type Order struct {",
  "\tID string",
  "}",
})
write(
  "domain/order/repository.go",
  { "package order", "", "type OrderRepository interface {", "\tSave(o *Order) error", "}" }
)
write("domain/order/misnamed.go", { "package order", "", "type PaymentService struct{}" })
write("domain/note/note.go", { "package note", "", "type Note struct {", "\tID string", "}" })
write("application/place_order.go", { "package application", "", "type PlaceOrder struct{}" })
write(
  "infrastructure/postgres/order_repository.go",
  { "package postgres", "", "type PostgresOrderRepository struct{}" }
)
write(
  "cmd/api/main.go",
  { "package main", "", 'import "example.com/shop/infrastructure/postgres"', "", "func main() {}" }
)

write("util/helpers.go", { "package util", "", "type Helper struct{}" }) -- fuera de toda capa: ni se lee
local idx
ddd_index.reset()
ddd_index.get(proj, function(i)
  idx = i
end)
vim.wait(5000, function()
  return idx ~= nil
end, 20)
eq(
  "índice: archivos, capas y tipos",
  { #idx.list, idx.counts.domain, idx.counts.application, idx.counts.infrastructure },
  { 7, 4, 1, 1 }
)
eq(
  "índice: lo que no está en una capa no se lee, pero se cuenta",
  { idx.files["util/helpers.go"], idx.seen },
  { nil, 8 }
)
local viol = ddd_rules.violations(idx)
local kinds = {}
for _, v in ipairs(viol) do
  kinds[#kinds + 1] = v.rule .. "@" .. v.file
end
eq("violaciones: dominio→infraestructura, framework y nombre (y NO la raíz de composición)", kinds, {
  "framework@domain/order/order.go",
  "dependency@domain/order/order.go",
  "naming@domain/order/misnamed.go",
})
eq("violación de dominio es ERROR", viol[1].severity, vim.diagnostic.severity.ERROR)
local aggs = ddd_rules.aggregates(idx)
local by_agg = {}
for _, a in ipairs(aggs) do
  by_agg[a.name] = a
end
eq("agregados: Order completo, Note sin puerto", {
  #aggs,
  by_agg.Order.port and by_agg.Order.port.name,
  by_agg.Order.impl and by_agg.Order.impl.name,
  by_agg.Order.usecases[1],
  by_agg.Note.port,
}, { 2, "OrderRepository", "PostgresOrderRepository", "PlaceOrder", nil })
if vim.fn.executable "rg" == 1 then
  local done
  ddd_rules.wire(idx, aggs, function()
    done = true
  end)
  vim.wait(5000, function()
    return done
  end, 20)
  eq("cableado: la implementación solo vive en su archivo → no cableada", by_agg.Order.wired, false)
  write("cmd/api/main.go", { "package main", "", "var repo = &postgres.PostgresOrderRepository{}" })
  ddd_index.reset()
  idx = nil
  ddd_index.get(proj, function(i)
    idx = i
  end)
  vim.wait(5000, function()
    return idx ~= nil
  end, 20)
  aggs = ddd_rules.aggregates(idx)
  done = nil
  ddd_rules.wire(idx, aggs, function()
    done = true
  end)
  vim.wait(5000, function()
    return done
  end, 20)
  for _, a in ipairs(aggs) do
    by_agg[a.name] = a
  end
  eq("cableado: referenciada desde cmd/main.go → cableada", by_agg.Order.wired, true)
end
local naming = ddd_naming.profile(idx)
eq(
  "nomenclatura deducida: snake_case y rol repository",
  { naming.style, naming.roles[1] and naming.roles[1].name },
  { "snake", "repository" }
)
eq("sugerencia de archivo con el estilo del proyecto", {
  ddd_naming.suggest(naming, "go", "Note", "repository"),
  ddd_naming.suggest({ style = "dotted" }, "ts", "OrderItem", "entity"),
  ddd_naming.suggest({ style = "pascal" }, "java", "Order", "repository"),
}, { "note_repository.go", "order-item.entity.ts", "OrderRepository.java" })
local steps = ddd_rules.next_steps(idx, aggs, naming)
local joined = table.concat(
  vim.tbl_map(function(st)
    return st.text
  end, steps),
  "\n"
)
eq("qué falta: puerto de Note con nombre de archivo del proyecto, y caso de uso", {
  joined:find("repository port for Note", 1, true) ~= nil,
  joined:find("note_repository.go", 1, true) ~= nil,
  joined:find("mentions Note", 1, true) ~= nil,
}, { true, true, true })
local section = ddd_profile.build(
  idx,
  "domain/order/order.go",
  naming,
  { by_agg.Order },
  vim.tbl_filter(function(v)
    return v.file == "domain/order/order.go"
  end, viol)
)
eq("sección <ddd>: capa, dependencias permitidas, convención, pieza relacionada y violaciones", {
  section:find("layer: domain (may depend on: domain)", 1, true) ~= nil,
  section:find("files: snake_case", 1, true) ~= nil,
  section:find("Order: port OrderRepository", 1, true) ~= nil,
  section:find("violation line 5", 1, true) ~= nil,
  section:find("Go: constructor New<T>", 1, true) ~= nil,
}, { true, true, true, true, true })
eq("sección <ddd> compacta (< 1800 caracteres)", #section < 1800, true)
-- el proveedor completo sobre un buffer real
local ddd_provider = require "agent.context.providers.ddd"
local pb = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(pb, proj .. "/domain/order/order.go")
vim.api.nvim_buf_set_lines(pb, 0, -1, false, vim.fn.readfile(proj .. "/domain/order/order.go"))
vim.bo[pb].filetype = "go"
local provided
ddd_provider.collect({
  buf = pb,
  lines = { "type Order struct {", "\tID string", "}" },
  first = 8,
  last = 10,
  path = "domain/order/order.go",
}, function(t)
  provided = t
end)
vim.wait(5000, function()
  return provided ~= nil
end, 20)
eq("proveedor ddd: sección con la capa del archivo", provided and provided:find("layer: domain", 1, true) ~= nil, true)
-- acciones DDD: registro propio, nombres distintos en el historial, contexto con <ddd>
local ddd_actions = require "agent.ddd.actions"
eq(
  "acciones DDD: nombres aparte y todas piden <ddd>",
  vim.tbl_map(function(a)
    return { a.name, vim.tbl_contains(a.context, "ddd") }
  end, ddd_actions.list()),
  {
    { "ddd_implement", true },
    { "ddd_review", true },
    { "ddd_fix", true },
    { "ddd_missing", true },
    { "ddd_ask", true },
  }
)
vim.fn.delete(proj, "rf")

-- hallazgos persistentes: guardar, restaurar reubicando por el texto de la línea, descartar lo que ya no existe
local persist = require "agent.persist"
local ptmp = vim.fn.tempname() .. ".json"
persist.use(ptmp)
eq("reubicar: la misma línea, desplazada, o ausente", {
  persist.reanchor({ "a", "b", "c" }, { line = 2, text = "b" }),
  persist.reanchor({ "x", "y", "a", "b", "c" }, { line = 2, text = "b" }),
  persist.reanchor({ "a", "c" }, { line = 2, text = "b" }),
}, { 2, 4, nil })
eq(
  "reubicar: dos coincidencias, la más cercana",
  persist.reanchor({ "}", "x", "}", "y", "}" }, { line = 4, text = "}" }),
  3
)

local ffile = vim.fn.tempname() .. ".go"
vim.fn.writefile({ "package p", "", "func A() {", "\treturn 1", "}", "", "func B() {", "\treturn 2", "}" }, ffile)
local fbuf = vim.fn.bufadd(ffile)
vim.fn.bufload(fbuf)
local fns = vim.api.nvim_create_namespace "agent.findings"
vim.diagnostic.set(fns, fbuf, {
  {
    lnum = 3,
    col = 0,
    message = "A returns a magic number",
    severity = vim.diagnostic.severity.WARN,
    source = "agent",
  },
  { lnum = 7, col = 0, message = "B returns a magic number", severity = vim.diagnostic.severity.INFO, source = "ddd" },
})
persist.sync(fbuf, "findings")
eq("persistencia: guarda 2 hallazgos con el texto de su línea", persist.count(), 2)
-- "otra sesión": sin diagnósticos, se restauran al abrir
vim.diagnostic.reset(fns, fbuf)
persist.restore(fbuf)
local back = vim.diagnostic.get(fbuf, { namespace = fns })
eq(
  "persistencia: restaura mensajes, severidades y líneas",
  { #back, back[1].message, back[1].lnum, back[2].source, back[2].severity },
  { 2, "A returns a magic number", 3, "ddd", vim.diagnostic.severity.INFO }
)
-- el código se movió (3 líneas nuevas arriba): se reubica por el texto
vim.diagnostic.reset(fns, fbuf)
vim.api.nvim_buf_set_lines(fbuf, 0, 0, false, { "// l1", "// l2", "// l3" })
persist.restore(fbuf)
back = vim.diagnostic.get(fbuf, { namespace = fns })
table.sort(back, function(a, b)
  return a.lnum < b.lnum
end)
eq(
  "persistencia: tras desplazar el código, se reubican (líneas 6 y 10)",
  { #back, back[1].lnum, back[2].lnum },
  { 2, 6, 10 }
)
-- una línea reescrita: ese hallazgo se descarta, el otro sigue
vim.diagnostic.reset(fns, fbuf)
vim.api.nvim_buf_set_lines(fbuf, 6, 7, false, { "\treturn computeA()" })
persist.restore(fbuf)
back = vim.diagnostic.get(fbuf, { namespace = fns })
eq(
  "persistencia: lo reescrito se descarta y se limpia de lo guardado",
  { #back, back[1].message, persist.count() },
  { 1, "B returns a magic number", 1 }
)
-- el proveedor `findings` lo ve; `review` y `ddd review` no (no deben partir de lo que dijo el review anterior)
local findings_provider = require "agent.context.providers.findings"
local fout
findings_provider.collect({ buf = fbuf, first = 9, last = 12 }, function(t)
  fout = t or ""
end)
eq(
  "proveedor findings: línea, severidad, origen, mensaje y código",
  fout,
  "L11 INFO[ddd]: B returns a magic number | return 2"
)
eq("review y ddd review NO leen hallazgos anteriores", {
  vim.tbl_contains(actions.get("review").context, "findings"),
  vim.tbl_contains(require("agent.ddd.actions").get("review").context, "findings"),
}, { false, false })
eq("fix y ddd fix SÍ los leen", {
  vim.tbl_contains(actions.get("fix").context, "findings"),
  vim.tbl_contains(require("agent.ddd.actions").get("fix").context, "findings"),
}, { true, true })
-- resolver un rango reescrito
require("agent.output.findings").resolve(fbuf, 9, 12)
eq(
  "resolver: el rango reescrito se queda sin hallazgos, también en lo guardado",
  { #vim.diagnostic.get(fbuf, { namespace = fns }), persist.count() },
  { 0, 0 }
)
-- el check de fix: sin diagnósticos no hay nada que arreglar
local ddd_fix = require("agent.ddd.actions").get "fix"
eq("ddd fix: sin nada por atender lo dice", ddd_fix.check { buf = fbuf, first = 1, last = 12 } ~= nil, true)
vim.diagnostic.set(fns, fbuf, { { lnum = 9, col = 0, message = "x", severity = 2, source = "ddd" } })
eq("ddd fix: con un hallazgo en el rango, procede", ddd_fix.check { buf = fbuf, first = 8, last = 12 }, nil)
-- ddd: el diagnóstico del proyecto se guarda por archivo y `forget_all` lo limpia
persist.replace_all(
  "ddd",
  { [ffile] = { { line = 5, severity = 1, message = "domain imports infra", source = "ddd" } } }
)
eq("persistencia ddd: guardado con el texto de la línea", persist.count(), 1)
persist.forget_all "ddd"
eq("forget_all limpia una clave en todos los archivos", persist.count(), 0)
vim.diagnostic.reset(fns, fbuf)
vim.fn.delete(ffile)
vim.fn.delete(ptmp)
persist.use(nil)

-- regresión: la UI del agente define sus colores SIN pasar por la fachada `agent` (el menú DDD no la carga;
-- sin esto, si DDD era lo primero que usabas, bloque, título y paneles salían en blanco plano)
for _, mod in ipairs {
  "agent.ui.panel",
  "agent.ui.inline",
  "agent.pipeline",
  "agent.ui.float",
  "agent.ui.status",
  "agent.ui.preview",
} do
  package.loaded["agent.ui.highlights"], package.loaded[mod] = nil, nil
  vim.api.nvim_set_hl(0, "AgentTitle", {})
  vim.api.nvim_set_hl(0, "AgentInputTitle", {})
  require(mod)
  local t, i = vim.api.nvim_get_hl(0, { name = "AgentTitle" }), vim.api.nvim_get_hl(0, { name = "AgentInputTitle" })
  eq(
    "colores: '" .. mod .. "' define los grupos del agente por sí solo",
    { t.fg ~= nil, i.fg ~= nil and i.bg ~= nil },
    { true, true }
  )
end
require("agent.ui.highlights").ensure()

-- CONTRATOS: el puerto que implementa un adaptador, lo que le falta, un ejemplo hermano y el esquema de su tabla
local cnames = require "agent.repository.contracts.names"
local ccontracts = require "agent.repository.contracts"
local cdiscovery = require "agent.discovery"
local cschema = require "agent.repository.contracts.schema"
eq("nombres: del adaptador al puerto y a la entidad", {
  cnames.candidates "PostgresOrderRepository",
  cnames.candidates "OrderRepositoryImpl",
  cnames.candidates "pgOrderRepository",
  cnames.entity_of "PostgresOrderRepository",
  cnames.entity_of "InMemoryNoteStore",
  cnames.looks_like_implementation "OrderService",
}, { { "OrderRepository" }, { "OrderRepository" }, { "OrderRepository" }, "Order", "Note", false })
eq(
  "nombres: tabla en plural primero (order es palabra reservada)",
  { cnames.tables "OrderItem", cnames.tables "Category", cnames.tables "Address" },
  { { "order_items", "order_item" }, { "categories", "category" }, { "addresses", "address" } }
)
eq("métodos de un puerto: Go, TypeScript, Python y Rust", {
  ccontracts.port_methods(
    { "type R interface {", "\tSave(ctx context.Context, o *Order) error", "\tByID(id string) (*Order, error)", "}" },
    "go"
  ),
  ccontracts.port_methods(
    { "interface R {", "  save(o: Order): Promise<void>;", "  byId<T>(id: string): Promise<Order>;", "}" },
    "ts"
  ),
  ccontracts.port_methods({ "class R(Protocol):", "    def save(self, o): ...", "    def by_id(self, id): ..." }, "py"),
  ccontracts.port_methods(
    { "trait R {", "    fn save(&self, o: &Order);", "    fn by_id(&self, id: &str) -> Option<Order>;", "}" },
    "rs"
  ),
}, { { "Save", "ByID" }, { "save", "byId" }, { "save", "by_id" }, { "save", "by_id" } })

local cp = vim.fn.tempname()
local function cwrite(rel, lines)
  local dir = vim.fn.fnamemodify(rel, ":h")
  vim.fn.mkdir(dir == "." and cp or (cp .. "/" .. dir), "p")
  vim.fn.writefile(lines, cp .. "/" .. rel)
end
cwrite("go.mod", { "module example.com/shop", "go 1.22", "require github.com/jackc/pgx/v5 v5.5.0" })
cwrite("internal/domain/order/order.go", {
  "package order",
  "",
  "type Order struct {",
  "\tID string",
  "\tCustomerID string",
  "\tTotal int64",
  "\tStatus string",
  "}",
})
cwrite("internal/domain/order/repository.go", {
  "package order",
  "",
  "type OrderRepository interface {",
  "\tSave(ctx context.Context, o *Order) error",
  "\tByID(ctx context.Context, id string) (*Order, error)",
  "\tDelete(ctx context.Context, id string) error",
  "}",
})
cwrite("internal/infrastructure/postgres/note_repository.go", {
  "package postgres",
  "",
  'import "database/sql"',
  "",
  "type PostgresNoteRepository struct{ db *sql.DB }",
  "",
  "func NewPostgresNoteRepository(db *sql.DB) *PostgresNoteRepository { return &PostgresNoteRepository{db: db} }",
  "",
  "func (r *PostgresNoteRepository) ByID(ctx context.Context, id string) (*note.Note, error) {",
  '\trow := r.db.QueryRowContext(ctx, "SELECT id, title FROM notes WHERE id = $1", id)',
  "\tvar n note.Note",
  "\tif err := row.Scan(&n.ID, &n.Title); err != nil {",
  '\t\treturn nil, fmt.Errorf("note by id: %w", err)',
  "\t}",
  "\treturn &n, nil",
  "}",
})
cwrite("internal/infrastructure/postgres/order_repository.go", {
  "package postgres",
  "",
  'import "database/sql"',
  "",
  "type PostgresOrderRepository struct{ db *sql.DB }",
  "",
  "func (r *PostgresOrderRepository) Save(ctx context.Context, o *order.Order) error { return nil }",
})
cwrite("db/migrations/0001_orders.sql", {
  "CREATE TABLE orders (",
  "  id uuid PRIMARY KEY,",
  "  customer_id uuid NOT NULL,",
  "  total_cents bigint NOT NULL,",
  "  status text NOT NULL DEFAULT 'pending',",
  "  created_at timestamptz NOT NULL DEFAULT now()",
  ");",
})
cwrite(
  "db/migrations/0002_orders_notes.sql",
  { "ALTER TABLE orders ADD COLUMN notes text;", "CREATE INDEX idx_orders_customer ON orders (customer_id);" }
)

local function open_target(rel, row, scope)
  local b = vim.fn.bufadd(cp .. "/" .. rel)
  vim.fn.bufload(b)
  vim.bo[b].filetype = "go"
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  return b, assert(target_mod.resolve(b, scope, nil))
end
local cb_, ctarget = open_target("internal/infrastructure/postgres/order_repository.go", 7, "type")
eq(
  "scope type: desde un método de Go resuelve al struct de su receptor",
  { ctarget.kind, ctarget.name, ctarget.first },
  { "class", "PostgresOrderRepository", 5 }
)
local subject = ccontracts.subject(ctarget)
eq("sujeto del objetivo", subject, "PostgresOrderRepository")
-- con el cursor SOBRE el struct de Go el nombre vive en `type_spec`: el objetivo debe llevarlo igualmente
local _, on_struct = open_target("internal/infrastructure/postgres/order_repository.go", 5, "type")
eq(
  "cursor sobre `type X struct`: el objetivo trae su nombre",
  { on_struct.kind, on_struct.name },
  { "class", "PostgresOrderRepository" }
)
open_target("internal/infrastructure/postgres/order_repository.go", 7, "type")
eq("puertos explícitos: Go, TS, Python y Rust", {
  (function()
    local b = with_buffer("go", { "var _ order.OrderRepository = (*PostgresOrderRepository)(nil)" }, 1)
    return ccontracts.explicit_ports({ buf = b }, "PostgresOrderRepository")
  end)(),
  (function()
    local b = with_buffer("typescript", { "class PgRepo implements OrderRepository, Closeable {" }, 1)
    return ccontracts.explicit_ports({ buf = b }, "PgRepo")
  end)(),
  (function()
    local b = with_buffer("python", { "class PgRepo(OrderRepository, Protocol):" }, 1)
    return ccontracts.explicit_ports({ buf = b }, "PgRepo")
  end)(),
  (function()
    local b = with_buffer("rust", { "impl OrderRepository for PgRepo {" }, 1)
    return ccontracts.explicit_ports({ buf = b }, "PgRepo")
  end)(),
}, { { "OrderRepository" }, { "OrderRepository", "Closeable" }, { "OrderRepository" }, { "OrderRepository" } })

if vim.fn.executable "rg" == 1 then
  vim.api.nvim_set_current_buf(cb_)
  local port
  ccontracts.find_port(cp, ctarget, "PostgresOrderRepository", function(p)
    port = p or false
  end)
  vim.wait(5000, function()
    return port ~= nil
  end, 20)
  eq(
    "puerto encontrado por nombre, con sus métodos",
    { port and port.name, port and port.methods },
    { "OrderRepository", { "Save", "ByID", "Delete" } }
  )
  local implemented, ctor = ccontracts.implemented(ctarget, "PostgresOrderRepository", "go")
  eq(
    "implementados: Save sí, ByID y Delete no; sin constructor",
    { implemented.Save, implemented.ByID, ctor },
    { true, nil, false }
  )
  local sib
  ccontracts.sibling(cp, ctarget, "PostgresOrderRepository", "go", { "ByID", "Delete" }, function(s)
    sib = s or false
  end)
  vim.wait(5000, function()
    return sib ~= nil
  end, 20)
  eq("hermano: otra implementación, con el método que falta y su constructor", {
    sib and sib.type,
    sib and sib.method,
    sib and sib.method_lines and sib.method_lines[2]:find("$1", 1, true) ~= nil,
    sib and sib.ctor_lines ~= nil,
  }, { "PostgresNoteRepository", "ByID", true, true })

  local found
  cschema.find(cp, "Order", function(f)
    found = f or false
  end)
  vim.wait(5000, function()
    return found ~= nil
  end, 20)
  local created = found and table.concat(found.tables[1].lines, "\n") or ""
  eq("esquema: CREATE TABLE de la entidad y los cambios posteriores", {
    created:find("total_cents bigint", 1, true) ~= nil,
    found and #found.changes,
    found and found.changes[1]:find("ADD COLUMN notes", 1, true) ~= nil,
  }, { true, 2, true })
  local env = cschema.environment(cp, "go", created, { "database/sql" })
  eq(
    "entorno: postgres (por la sintaxis) con pgx y database/sql, parámetros numerados",
    { env.dialect, env.driver, env.access[1], env.line:find("$1, $2", 1, true) ~= nil },
    { "postgres", "pgx", "database/sql", true }
  )
  eq(
    "entorno agnóstico: MySQL por su sintaxis → `?`",
    cschema
      .environment(cp, "go", "CREATE TABLE t (id INT AUTO_INCREMENT) ENGINE=InnoDB;", {}).line
      :find("? (positional)", 1, true) ~= nil,
    true
  )
  eq(
    "sin esquema ni driver, no se inventa un dialecto",
    cschema.environment("/nonexistent", "go", nil, {}).dialect,
    nil
  )

  -- los proveedores completos
  local out
  require("agent.context.providers.contracts").collect(ctarget, function(t)
    out = t or ""
  end, { names = {}, action = { examples = true } })
  vim.wait(5000, function()
    return out ~= nil
  end, 20)
  eq("proveedor contracts: puerto, faltantes y ejemplo (con rutas)", {
    out:find("port OrderRepository (internal/domain/order/repository.go:3)", 1, true) ~= nil,
    out:find("implemented Save · missing ByID, Delete", 1, true) ~= nil,
    out:find("constructor: missing (NewPostgresOrderRepository)", 1, true) ~= nil,
    out:find(
      "example method ByID, from PostgresNoteRepository (internal/infrastructure/postgres/note_repository.go)",
      1,
      true
    ) ~= nil,
  }, { true, true, true, true })
  local no_example
  require("agent.context.providers.contracts").collect(ctarget, function(t)
    no_example = t or ""
  end, { names = {}, action = {} })
  vim.wait(5000, function()
    return no_example ~= nil
  end, 20)
  eq("sin `examples`, no se paga el ejemplo", no_example:find("example method", 1, true), nil)
  eq("contracts trae la entidad que el puerto nombra (y sus campos), aunque el objetivo no la mencione", {
    out:find("Order (internal/domain/order/order.go", 1, true) ~= nil,
    out:find("TotalCents int64", 1, true) ~= nil or out:find("Total int64", 1, true) ~= nil,
  }, { true, true })
  local sch
  require("agent.context.providers.schema").collect(ctarget, function(t)
    sch = t or ""
  end)
  vim.wait(5000, function()
    return sch ~= nil
  end, 20)
  eq("proveedor schema: dialecto, tabla real y cambios", {
    sch:find("db: postgres", 1, true) ~= nil,
    sch:find("CREATE TABLE orders", 1, true) ~= nil,
    sch:find("later changes:", 1, true) ~= nil,
  }, { true, true, true })
  -- silencioso si no es un adaptador
  local svc_b = with_buffer(
    "go",
    { "package order", "", "type OrderService struct{}", "", "func (s *OrderService) Place() {", "}" },
    5
  )
  vim.api.nvim_buf_set_name(svc_b, cp .. "/internal/application/service.go")
  local svc = assert(target_mod.resolve(svc_b, "function", nil))
  local c2, s2
  require("agent.context.providers.contracts").collect(svc, function(t)
    c2 = t or ""
  end, { names = {}, action = {} })
  require("agent.context.providers.schema").collect(svc, function(t)
    s2 = t or ""
  end)
  vim.wait(2000, function()
    return c2 ~= nil and s2 ~= nil
  end, 20)
  eq("un servicio no recibe ni puerto ni esquema (costo 0)", { c2, s2 }, { "", "" })
end
vim.fn.delete(cp, "rf")

-- NIVELES de la arquitectura: repository (<leader>aP) y service (<leader>aS), cada uno con su carpeta, su registro y su menú
local repo_check = require "agent.repository.check"
eq("repository check: columnas de un CREATE TABLE y campos de la entidad (sin importar mayúsculas ni guiones bajos)", {
  repo_check.columns {
    "CREATE TABLE orders (",
    "  id uuid PRIMARY KEY,",
    "  customer_id uuid NOT NULL,",
    "  total_cents bigint NOT NULL,",
    "  CONSTRAINT fk FOREIGN KEY (customer_id) REFERENCES c(id),",
    "  PRIMARY KEY (id)",
    ");",
  },
  vim.tbl_map(
    function(f)
      return f.key
    end,
    repo_check.fields(
      { "type Order struct {", "\tID string", "\tCustomerID string", "\tTotalCents int64", "\tNotes string", "}" },
      "go"
    )
  ),
}, { { "id", "customer_id", "total_cents" }, { "id", "customerid", "totalcents", "notes" } })
local service_ports = require "agent.service.ports"
eq("servicio: por nombre o por vivir en la capa de aplicación", {
  service_ports.looks_like_service("PlaceOrderService", "x.go"),
  service_ports.looks_like_service("PlaceOrder", "internal/application/place.go"),
  service_ports.looks_like_service("PostgresOrderRepository", "internal/infrastructure/x.go"),
}, { true, true, false })
eq("servicio: el campo que guarda el puerto, en Go, TS, Python y Java", {
  service_ports.field_name("type S struct {\n\torders order.OrderRepository\n}", "OrderRepository"),
  service_ports.field_name(
    "class S {\n  constructor(private readonly orders: OrderRepository) {}\n}",
    "OrderRepository"
  ),
  service_ports.field_name("def __init__(self, orders: OrderRepository):", "OrderRepository"),
  service_ports.field_name("private final OrderRepository orders;", "OrderRepository"),
}, { "orders", "orders", "orders", "orders" })
local deps = require "agent.service.deps"
local field, called, unknown = deps.analyse(
  "func (p *PlaceOrder) Run() {\n\tp.orders.ByID(ctx, id)\n\tp.orders.FindAll(ctx)\n\tp.orders.Save(ctx, o)\n}",
  "type PlaceOrder struct {\n\torders order.OrderRepository\n}",
  "",
  { name = "OrderRepository", methods = { "Save", "ByID", "Delete" } }
)
eq(
  "deps: llama a FindAll, que el puerto no declara",
  { field, called.ByID, called.Save, unknown },
  { "orders", true, true, { "FindAll" } }
)

local sp = vim.fn.tempname()
local function swrite(rel, lines)
  local dir = vim.fn.fnamemodify(rel, ":h")
  vim.fn.mkdir(dir == "." and sp or (sp .. "/" .. dir), "p")
  vim.fn.writefile(lines, sp .. "/" .. rel)
end
swrite("go.mod", { "module example.com/shop", "go 1.22" })
swrite("internal/domain/order/repository.go", {
  "package order",
  "",
  "type OrderRepository interface {",
  "\tSave(ctx context.Context, o *Order) error",
  "\tByID(ctx context.Context, id string) (*Order, error)",
  "}",
})
swrite(
  "internal/domain/order/mailer.go",
  { "package order", "", "type Mailer interface {", "\tSend(ctx context.Context, to string, body string) error", "}" }
)
swrite("internal/application/place_order.go", {
  "package application",
  "",
  "type PlaceOrder struct {",
  "\torders order.OrderRepository",
  "\tmailer order.Mailer",
  "}",
  "",
  "func NewPlaceOrder(orders order.OrderRepository, mailer order.Mailer) *PlaceOrder {",
  "\treturn &PlaceOrder{orders: orders, mailer: mailer}",
  "}",
  "",
  "func (p *PlaceOrder) Run(ctx context.Context) error {",
  "\treturn nil",
  "}",
})
swrite(
  "internal/infrastructure/postgres/order_repository.go",
  { "package postgres", "", "type PostgresOrderRepository struct{}" }
)
if vim.fn.executable "rg" == 1 then
  local b = vim.fn.bufadd(sp .. "/internal/application/place_order.go")
  vim.fn.bufload(b)
  vim.bo[b].filetype = "go"
  vim.api.nvim_set_current_buf(b)
  vim.api.nvim_win_set_cursor(0, { 12, 0 })
  local stgt = assert(target_mod.resolve(b, "function", nil))
  local sdeps
  service_ports.dependencies(sp, stgt, "PlaceOrder", "go", function(l)
    sdeps = l
  end)
  vim.wait(5000, function()
    return sdeps ~= nil
  end, 20)
  eq("servicio: encuentra los puertos que recibe (campos y constructor) con sus métodos", {
    #sdeps,
    sdeps[1] and sdeps[1].name,
    sdeps[1] and sdeps[1].methods,
    sdeps[2] and sdeps[2].name,
    sdeps[2] and sdeps[2].methods,
  }, { 2, "Mailer", { "Send" }, "OrderRepository", { "Save", "ByID" } })
  local pout
  require("agent.context.providers.ports").collect(stgt, function(t)
    pout = t or ""
  end, { names = {}, action = {} })
  vim.wait(5000, function()
    return pout ~= nil
  end, 20)
  eq("proveedor ports: cada puerto con su ruta y 'llama solo a estos métodos'", {
    pout:find("port OrderRepository (internal/domain/order/repository.go:3): call only these methods", 1, true) ~= nil,
    pout:find("Send(ctx context.Context, to string, body string) error", 1, true) ~= nil,
  }, { true, true })
  local impls
  require("agent.discovery").implementations(sp, "OrderRepository", "go", function(l)
    impls = l
  end)
  vim.wait(5000, function()
    return impls ~= nil
  end, 20)
  eq(
    "implementaciones de un puerto por nombre",
    { #impls, impls[1] and impls[1].name },
    { 1, "PostgresOrderRepository" }
  )
  local used
  require("agent.discovery").referenced_elsewhere(
    sp,
    "PostgresOrderRepository",
    sp .. "/internal/infrastructure/postgres/order_repository.go",
    function(u)
      used = u
    end
  )
  vim.wait(5000, function()
    return used ~= nil
  end, 20)
  eq("referenced_elsewhere: nadie lo usa fuera de su archivo", used, false)
  -- un handler/otra función no recibe puertos
  local fb = with_buffer("go", { "package x", "", "func Helper() {", "}" }, 3)
  local ftgt = assert(target_mod.resolve(fb, "function", nil))
  local fout
  require("agent.context.providers.ports").collect(ftgt, function(t)
    fout = t or ""
  end, { names = {}, action = {} })
  vim.wait(2000, function()
    return fout ~= nil
  end, 20)
  eq("una función cualquiera no recibe puertos (costo 0)", fout, "")
end
vim.fn.delete(sp, "rf")
-- registros y menús por nivel
local repo_actions, service_actions = require "agent.repository.actions", require "agent.service.actions"
eq("acciones por nivel: nombres propios y contrato completo", {
  vim.tbl_map(function(a)
    return a.name
  end, repo_actions.list()),
  vim.tbl_map(function(a)
    return a.name
  end, service_actions.list()),
}, { { "repo_port", "repo_implement", "repo_review" }, { "service_implement", "service_review" } })
for _, a in ipairs(vim.list_extend(vim.list_extend({}, repo_actions.list()), service_actions.list())) do
  eq(
    "acción '" .. a.name .. "' cumple el contrato",
    (a.label and a.desc and a.key and a.output and a.system and a.task and a.context) ~= nil,
    true
  )
end
local function keys_of(menu)
  return vim.tbl_map(function(m)
    return m[1]
  end, menu.maps)
end
local main_keys = keys_of(require "menus.agent")
eq("menú principal sin `port` (vive en su nivel)", vim.tbl_contains(main_keys, "p"), false)
eq(
  "menú Repository (<leader>aP): port, implement, review, check",
  { require("menus.agent_repository").prefix, keys_of(require "menus.agent_repository") },
  { "aP", { "p", "i", "r", "c" } }
)
eq(
  "menú Service (<leader>aS): implement, review, deps",
  { require("menus.agent_service").prefix, keys_of(require "menus.agent_service") },
  { "aS", { "i", "r", "d" } }
)
local prefixes = {}
for _, ctx in ipairs(require("menus").contexts()) do
  prefixes[#prefixes + 1] = ctx.prefix
end
eq(
  "los tres niveles están registrados como grupos del leader",
  { vim.tbl_contains(prefixes, "aD"), vim.tbl_contains(prefixes, "aP"), vim.tbl_contains(prefixes, "aS") },
  { true, true, true }
)
eq(
  "la acción `port` ya no está en el registro principal",
  pcall(function()
    return require("agent.actions").get "port"
  end),
  false
)

-- registro de acciones: contrato mínimo
for _, a in ipairs(require("agent.actions").list()) do
  local ok = a.label and a.desc and a.key and (a.handler or (a.output and a.system and a.task))
  eq("acción '" .. a.name .. "' cumple el contrato", ok and true or false, true)
end
print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
