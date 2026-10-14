-- Agent tests (parsers, protocol, target). No network or tokens.
-- Run by scripts/test-agent.sh inside headless nvim with the real config.
local fails = 0
-- headless `print` does not end the line: write to stdout by hand
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
eq("extract_code basic", code, { "func A() {", "}" })
eq("needs-import", needs, "strings, fmt")
code, needs = protocol.extract_code "Here it is:\n```lua\nlocal x = 1\n```\nneeds-import: none"
eq("ignores leading prose and 'none'", { code, needs }, { { "local x = 1" }, nil })
code = protocol.extract_code("```md\n# t\n```lua\nx=1\n```\ntext\n```", { "```lua", "x=1", "```" })
eq("nested fence (markdown target): closes on the LAST one", code, { "# t", "```lua", "x=1", "```", "text" })
local c, _, err = protocol.extract_code "no block"
eq("no block → error", { c, err ~= nil }, { nil, true })
c, _, err = protocol.extract_code "```go\nfunc A() {"
eq("unclosed block → error", { c, err ~= nil }, { nil, true })
eq("empty block = empty list", protocol.extract_code "```\n```", {})

-- several blocks (draft + corrected): the last one that starts like the target wins
local target_fn = { "/// doc", "fn f() {", "}" }
local draft_and_fix =
  "```rust\n/// doc\nfn f() { 1 }\n```\n\nWait, that is wrong. Corrected:\n\n```rust\n/// doc\nfn f() { 2 }\n```\nneeds-import: none"
local picked, _, _, n_blocks = protocol.extract_code(draft_and_fix, target_fn)
eq(
  "several blocks: picks the last one that starts like the target",
  { picked, n_blocks },
  { { "/// doc", "fn f() { 2 }" }, 2 }
)
local code_and_example = "```rust\n/// doc\nfn f() { 1 }\n```\nExample:\n```rust\nlet x = f();\n```"
eq(
  "several blocks: a later example does not win",
  (protocol.extract_code(code_and_example, target_fn)),
  { "/// doc", "fn f() { 1 }" }
)
eq(
  "several blocks: if none matches, the first",
  (protocol.extract_code("```\nA\n```\n```\nB\n```", { "zzz" })),
  { "A" }
)
eq(
  "markdown target (with fences): first to last",
  (protocol.extract_code("```md\n```go\nx\n```\n```", { "```go", "x", "```" })),
  { "```go", "x", "```" }
)
eq("unclosed block after a valid one: ignored", (protocol.extract_code("```a\nok\n```\n```b\nbroken", nil)), { "ok" })

-- findings
local f =
  protocol.parse_findings "L12|warn|something wrong\ngarbage\n  L3 | ERROR | other  \nL9|weird|unknown severity\nL1|info|"
eq("findings: 3 valid (empty and garbage are ignored)", #f, 3)
eq(
  "severity",
  { f[1].severity, f[2].severity, f[3].severity },
  { vim.diagnostic.severity.WARN, vim.diagnostic.severity.ERROR, vim.diagnostic.severity.INFO }
)
eq("line and message", { f[2].line, f[2].message }, { 3, "other" })
eq("is_ok", { protocol.is_ok " ok \n", protocol.is_ok "L1|warn|x" }, { true, false })

-- chunked ndjson
local nd = require "agent.backends.ndjson"
local got = {}
local feed = nd.new(function(o)
  got[#got + 1] = o.n
  return tostring(o.n)
end)
local out = (feed '{"n":1}\n{"n"' or "") .. (feed ':2}\n\n{"n":3}' or "") .. (feed "\n" or "")
eq("ndjson reassembles cut chunks", { got, out }, { { 1, 2, 3 }, "123" })

-- claude parser
local claude = require "agent.backends.claude"
local p = claude.parser()
local d1 =
  p.feed '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Ho"}}}\n'
local d2 =
  p.feed '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"x"}}}\n{"type":"result","is_error":false,"result":"Hola","total_cost_usd":0.001,"duration_ms":900,"usage":{"input_tokens":2,"cache_creation_input_tokens":500,"cache_read_input_tokens":100,"output_tokens":7}}\n'
local r = p.finish(0, "")
eq("claude: text delta, not thinking", { d1, d2 }, { "Ho", nil })
eq(
  "claude: result",
  { r.ok, r.text, r.usage.tokens_in, r.usage.tokens_out, r.usage.cost },
  { true, "Hola", 602, 7, 0.001 }
)
local pe = claude.parser()
pe.feed '{"type":"result","is_error":true,"result":"usage limit reached"}\n'
eq("claude: CLI error", pe.finish(1, ""), { ok = false, err = "usage limit reached" })
eq(
  "claude: output without result and code≠0 uses stderr",
  claude.parser().finish(1, "boom\n"),
  { ok = false, err = "boom" }
)
local spec = claude.build { system = "SYS", prompt = "P", model = "haiku", effort = "low", action = "review" }
eq("claude: key argv", {
  vim.tbl_contains(spec.cmd, "--tools"),
  spec.cmd[vim.fn.index(spec.cmd, "--setting-sources") + 2],
  spec.stdin,
  spec.cmd[vim.fn.index(spec.cmd, "--effort") + 2],
  vim.tbl_contains(spec.cmd, "--max-budget-usd"),
}, { true, "", "P", "low", true })
eq("claude: no prompt cache by default", spec.env, { DISABLE_PROMPT_CACHING = "1" })

-- opencode parser + build
local oc = require "agent.backends.opencode"
local q = oc.parser()
local e1 =
  q.feed '{"type":"step_start","part":{"type":"step-start"}}\n{"type":"text","part":{"id":"p1","type":"text","text":"Hel"}}\n'
local e2 =
  q.feed '{"type":"text","part":{"id":"p1","type":"text","text":"Hello"}}\n{"type":"step_finish","part":{"tokens":{"input":10,"output":5,"cache":{"read":3,"write":2}},"cost":0.002}}\n'
local qr = q.finish(0, "")
eq("opencode: emits only what is new from a growing part", { e1, e2 }, { "Hel", "lo" })
eq(
  "opencode: final text and usage",
  { qr.ok, qr.text, qr.usage.tokens_in, qr.usage.tokens_out, qr.usage.cost },
  { true, "Hello", 15, 5, 0.002 }
)
local qe = oc.parser()
qe.feed '{"type":"error","error":{"name":"APIError","data":{"message":"Forbidden"}}}\n'
eq("opencode: error with message", qe.finish(1, ""), { ok = false, err = "Forbidden" })
eq("opencode: no text or error", oc.parser().finish(0, "").ok, false)
require("core.settings").agent.opencode.serve = false -- hermetic: do not start a real `opencode serve`
local ospec =
  oc.build { system = "SYS", prompt = "PROMPT", model = "opencode-go/x", action = "explain", effort = "high" }
local cfg = vim.json.decode(ospec.env.OPENCODE_CONFIG_CONTENT)
eq(
  "opencode: ephemeral agent without tools",
  { cfg.agent["nvim-explain"].prompt, cfg.agent["nvim-explain"].tools.bash, cfg.agent["nvim-explain"].permission.edit },
  { "SYS", false, "deny" }
)
eq("opencode: argv", {
  ospec.cmd[vim.fn.index(ospec.cmd, "--agent") + 2],
  ospec.cmd[vim.fn.index(ospec.cmd, "--variant") + 2],
  ospec.cmd[#ospec.cmd],
  ospec.cmd[#ospec.cmd - 1],
}, { "nvim-explain", "high", "PROMPT", "--" })

-- opencode: the global MCP servers are turned off (their schemas were ~20k input tokens); JSONC tolerated
do
  local xdg = vim.fn.tempname()
  vim.fn.mkdir(xdg .. "/opencode", "p")
  vim.fn.writefile({
    "// comment",
    "{",
    '  "$schema": "https://opencode.ai/config.json", // trailing',
    "  /* block */",
    '  "mcp": {',
    '    "chrome": { "type": "local", "command": ["x"], "enabled": true },',
    '    "dart": { "type": "local", "command": ["y"] },',
    "  },",
    "}",
  }, xdg .. "/opencode/opencode.jsonc")
  local real_xdg = vim.env.XDG_CONFIG_HOME
  vim.env.XDG_CONFIG_HOME = xdg
  local mcp = oc.config().mcp
  eq("opencode: global MCP servers disabled", { mcp.chrome, mcp.dart }, { { enabled = false }, { enabled = false } })
  local own = require("core.settings").agent.opencode
  own.mcp = true
  eq("opencode: mcp = true leaves them alone", oc.config(), nil)
  own.mcp = false
  vim.env.XDG_CONFIG_HOME = xdg .. "/missing"
  eq("opencode: no global config, no override", oc.config(), nil)
  vim.env.XDG_CONFIG_HOME = real_xdg

  local fast = vim.json.decode(
    oc.build({ system = "S", prompt = "P", model = "opencode-go/deepseek-v4.1-flash", action = "docs" }).env.OPENCODE_CONFIG_CONTENT
  )
  eq("opencode: thinking off for listed models", fast.agent["nvim-docs"].options, { thinking = { type = "disabled" } })
  eq("opencode: thinking untouched for others", cfg.agent["nvim-explain"].options, nil)

  -- the private server's HTTP answer: ONE json object, no trailing newline
  local http = oc.parser()
  http.feed '{"info":{"tokens":{"input":50,"output":9,"cache":{"read":700,"write":0}},"cost":0.001},'
  http.feed '"parts":[{"type":"step-start"},{"type":"reasoning","text":"hmm"},{"type":"text","text":"```go\nx\n```"}]}'
  local hr = http.finish(0, "")
  eq(
    "opencode http: text and usage of the whole message",
    { hr.ok, hr.text, hr.usage.tokens_in, hr.usage.tokens_out, hr.usage.cost },
    { true, "```go\nx\n```", 750, 9, 0.001 }
  )
  local he = oc.parser()
  he.feed '{"name":"UnknownError","data":{"message":"Unexpected server error.","ref":"err_1"}}'
  eq("opencode http: error object", he.finish(0, ""), { ok = false, err = "Unexpected server error. (err_1)" })
  eq("opencode http: no session ready → cold path", require("agent.backends.opencode_server").post {}, nil)
end

-- diff and target without treesitter
local diff = require "agent.output.diff"
eq("diff: insertion at the start", diff.hunks({ "a", "b" }, { "x", "a", "b" })[1].a_start, 0)
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a note", "no parser", "", "another paragraph" })
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local target = require("agent.context.target").resolve(buf, "function", nil)
eq("target without parser = paragraph (lines 1-2)", { target.kind, target.first, target.last }, { "lines", 1, 2 })
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "" })
eq(
  "empty target → error",
  select(2, require("agent.context.target").resolve(buf, "function", nil)),
  "no code under the cursor"
)

-- models per tier. Hermetic: with an empty state, not with the model you chose in <leader>am
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
  eq("tier: docs runs on the light model", selection.current(docs).model, "haiku")
  eq(
    "tier: implement runs on the main one",
    selection.current(implement).model,
    require("core.settings").agent.claude.model
  )
  eq("tier: the light one does not inherit the effort", selection.current(docs).effort, nil)
  local settings = require("core.settings").agent
  settings.tiers.review = "light"
  eq("tier: settings.agent.tiers reassigns an action", selection.tier_of(actions.get "review"), "light")
  settings.tiers.review = nil
end
eq(
  "tier: explain and docs are light by default",
  { selection.tier_of(actions.get "explain"), selection.tier_of(actions.get "docs") },
  { "light", "light" }
)
eq(
  "tier: implement/fix/refactor/review/ask are main",
  vim.tbl_map(function(n)
    return selection.tier_of(actions.get(n))
  end, { "implement", "fix", "refactor", "review", "ask" }),
  { "main", "main", "main", "main", "main" }
)
package.loaded["agent.state"], package.loaded["agent.selection"] = real_state_mod, real_selection

-- the user's instruction only enters the optional variants; in the ones that already ask for text it goes in their `task`
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
eq("prompt: without an instruction there is no additional block", plain:find("Additional instruction", 1, true), nil)
eq(
  "prompt: with an instruction, it goes inside <task> and takes precedence",
  { with:find("Additional instruction", 1, true) ~= nil, with:find("print the numbers 1 to 5", 1, true) ~= nil },
  { true, true }
)
local _, ask = prompt.build(actions.get "ask", tgt, {}, "why?")
eq("prompt: ask does not duplicate the instruction", select(2, ask:gsub("why%?", "")), 1)
for _, n in ipairs { "implement", "docs", "fix" } do
  local a = actions.get(n)
  eq(
    "'" .. n .. "' asks for an optional instruction (empty Enter runs anyway)",
    { a.input ~= nil, a.input_optional },
    { true, true }
  )
end
for _, n in ipairs { "ask", "refactor" } do
  local a = actions.get(n)
  eq("'" .. n .. "' requires text", { a.input ~= nil, a.input_optional }, { true, nil })
end
eq(
  "review and explain run instantly (no field)",
  { actions.get("review").input, actions.get("explain").input },
  { nil, nil }
)
local keys, seen = {}, true
for _, a in ipairs(actions.list()) do
  local menu = a.advanced and "aA" or "a" -- each menu has its own keys: everyday <leader>a, Advanced <leader>aA
  keys[menu] = keys[menu] or {}
  seen = seen and not keys[menu][a.key]
  keys[menu][a.key] = true
end
eq("action keys are not repeated within a menu", seen, true)
local adv = require "menus.agent_advanced"
eq(
  "Advanced menu (<leader>aA): the batch actions and the queue",
  { adv.prefix, vim.tbl_map(function(m)
    return m[1]
  end, adv.maps) },
  { "aA", { "a", "o", "O", "p", "]", "[", "y", "l" } }
)
eq(
  "the everyday menu does not carry them",
  vim.tbl_filter(function(m)
    return vim.tbl_contains({ "A", "o", "O", "M", "]", "[", "Y", "Q" }, m[1])
  end, require("menus.agent").maps),
  {}
)
eq("handoff is only offered inside Herdr", actions.get("handoff").enabled ~= nil, true)

-- instruction recall (with a fake state: does not touch the real agent.json)
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
eq("history: most recent first and without duplicates", history.list "implement", { "a", "b" })
eq("history: each action has its own", history.list "docs", {})
for i = 1, 40 do
  history.push("x", "t" .. i)
end
eq("history: cap of 30", { #history.list "x", history.list("x")[1] }, { 30, "t40" })
package.loaded["agent.state"], package.loaded["agent.recall"] = real_state, nil

-- run history: store (JSONL), event folding, compaction, report and detail
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
store.append { t = "event", id = "orphan", ts = now, event = "accepted" } -- event without a run: ignored
vim.fn.writefile({ "{not json" }, tmp, "a") -- corrupt line: ignored
local runs = store.read()
local by = {}
for _, r in ipairs(runs) do
  by[r.id] = r
end
eq("history: 5 runs, most recent first", { #runs, runs[1].id }, { 5, "r5" })
eq(
  "history: folded outcomes",
  { by.r1.outcome, by.r2.outcome, by.r3.outcome, by.r3.detail, by.r4.outcome, by.r5.outcome },
  { "accepted", "rejected", "findings", 3, "error", "pending" }
)
local lines = report.build(runs, now)
local text = table.concat(lines, "\n")
eq("report: cumulative total", text:find("All time | 5 |", 1, true) ~= nil, true)
eq(
  "report: cost per applied change (1 accepted of 3 proposals)",
  text:find("1 of 3 proposals accepted", 1, true) ~= nil,
  true
)
eq("report: what was spent on proposals not applied", text:find("Spent on proposals not applied", 1, true) ~= nil, true)
eq("report: cache 0%", text:find "0%% of input tokens were cache reads" ~= nil, true)
eq("report: empty does not fail", report.build({}, now)[3], "_No runs recorded yet._")
eq("picker headline", report.headline(runs), "5 runs · $0.0183")
local d = table.concat(detail.build(by.r1), "\n")
eq(
  "detail: shows prompt, response and cost",
  { d:find("SYS", 1, true) ~= nil, d:find("RESP", 1, true) ~= nil, d:find("$0.0040", 1, true) ~= nil },
  { true, true, true }
)
local whole = detail.text(by.r1)
eq("copy all: metadata, result, events, instruction, response, system and message", {
  whole:find("# implement · claude/sonnet", 1, true) ~= nil,
  whole:find("accepted @", 1, true) ~= nil,
  whole:find("## Your instruction", 1, true) ~= nil,
  whole:find("RESP", 1, true) ~= nil,
  whole:find("SYS", 1, true) ~= nil,
  whole:find("MSG", 1, true) ~= nil,
  whole:sub(-1),
}, { true, true, true, true, true, true, "\n" })
eq("detail: a fence inside the text does not break the block", d:find("````text", 1, true) ~= nil, true)
eq(
  "format: money and tokens",
  { rfmt.money(0.00123), rfmt.money(2.5), rfmt.tokens(1234), rfmt.tokens(87) },
  { "$0.0012", "$2.50", "1.2k", "87" }
)
require("core.settings").agent.history.max_entries = 2
store.compact()
eq(
  "compact: 5 > 2×1.5 → the 2 most recent remain with their events",
  { #store.read(), store.read()[1].id },
  { 2, "r5" }
)
require("core.settings").agent.history.max_entries = 1000
os.remove(tmp)
store.use(nil)

-- types the target uses (treesitter, no LSP): the model must not guess the fields
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
    "Go types: receiver with its fields",
    { text:find("Done    bool", 1, true) ~= nil, text:find("Updated time.Time", 1, true) ~= nil },
    { true, true }
  )
  eq("Go types: follows a field's type (Tags []Tag)", text:find("type Tag struct", 1, true) ~= nil, true)
  eq(
    "Go types: does not include types nobody uses nor the target itself",
    { text:find("Unused", 1, true), text:find("SetDone", 1, true) },
    { nil, nil }
  )
  local o = collect(outline, b, { names = { "outline", "types" } })
  eq("outline: with <types> it does not repeat the type definitions", o:find("type Note struct", 1, true), nil)
  local o2 = collect(outline, b, { names = { "outline" } })
  eq("outline: without <types> it does list them", o2:find("type Note struct", 1, true) ~= nil, true)
  -- diagnostics: each message carries its code line (the target is not numbered)
  local ns = vim.api.nvim_create_namespace "test-agent-diag"
  vim.diagnostic.set(ns, b, { { lnum = 13, col = 0, message = "boom", severity = 1, source = "gopls" } })
  local d = collect(diagnostics, b)
  eq("diagnostic with its code line", d, "L14 ERROR: boom [gopls] | func (n *Note) SetDone(done bool) {")
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
    "Python types: the method's class, without the method itself",
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
    "Rust types: a method of `impl Note` brings `struct Note`",
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
  eq("TypeScript types: the parameter's interface", text:find("interface Note", 1, true) ~= nil, true)
end

if has_parser "java" then
  local b = with_buffer(
    "java",
    { "enum Kind { A, B }", "class Note {", "  private boolean done;", "  void setKind(Kind k) {", "  }", "}" },
    4
  )
  local text = collect(types, b)
  eq(
    "Java types: enum (which the query does not capture) and the method's class",
    { text:find("enum Kind", 1, true) ~= nil, text:find("private boolean done", 1, true) ~= nil },
    { true, true }
  )
end

-- `note:` and `needs-import:` after the block
local _, needs2, _, _, note2 =
  protocol.extract_code("```go\nx\n```\nneeds-import: strings\nnote: Note has no Done field; assumed one", { "x" })
eq("note: read alongside needs-import", { needs2, note2 }, { "strings", "Note has no Done field; assumed one" })
eq("note: none is ignored", select(5, protocol.extract_code("```go\nx\n```\nnote: none", { "x" })), nil)

-- coherent context policy: each action asks for what it needs, by priority
local function ctx_of(n)
  return actions.get(n).context
end
eq(
  "context: fix prioritizes diagnostics, then findings and contracts",
  { ctx_of("fix")[2], ctx_of("fix")[3], ctx_of("fix")[4] },
  { "diagnostics", "findings", "contracts" }
)
eq(
  "context: docs and explain receive types",
  { vim.tbl_contains(ctx_of "docs", "types"), vim.tbl_contains(ctx_of "explain", "types") },
  { true, true }
)
eq(
  "context: docs does not pay for outline or callees",
  { vim.tbl_contains(ctx_of "docs", "outline"), vim.tbl_contains(ctx_of "docs", "callees") },
  { false, false }
)
for _, n in ipairs { "implement", "review", "fix", "refactor", "ask", "explain", "docs" } do
  eq("context: '" .. n .. "' includes types", vim.tbl_contains(ctx_of(n), "types"), true)
end

-- regression: a `&Order{...}` literal is not another definition of `Order` (the Go query captures it as class.outer)
if has_parser "go" then
  local decls = require("agent.context.scopes").type_declarations(
    'package p\n\ntype Order struct{ ID string }\n\nfunc New() *Order {\n\treturn &Order{ID: "x"}\n}\n',
    "go"
  )
  eq(
    "types: a struct literal does not count as a definition",
    { #decls, decls[1] and decls[1].name, decls[1] and decls[1].first },
    { 1, "Order", 3 }
  )
end

-- constants associated with a type (Go's "enum") travel with it
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
    "types: the Status type brings its constants (Pending, Confirmed)",
    { text:find("type Status string", 1, true) ~= nil, text:find('Confirmed Status = "confirmed"', 1, true) ~= nil },
    { true, true }
  )
end

-- DDD: imports, layers, rules, aggregates, wiring, naming and the <ddd> section (synthetic Go project)
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
  "Go imports (block and alias)",
  specs(ddd_imports.extract({ "import (", '\t"fmt"', '\tdb "x/infrastructure/db"', ")" }, "go")),
  { "fmt", "x/infrastructure/db" }
)
eq(
  "TS imports",
  specs(ddd_imports.extract({ "import { A } from '../../infrastructure/db'", "const x = require('express')" }, "ts")),
  { "../../infrastructure/db", "express" }
)
eq(
  "Python imports",
  specs(ddd_imports.extract({ "from app.infrastructure.db import Session", "import os" }, "py")),
  { "app.infrastructure.db", "os" }
)
eq(
  "Java imports",
  specs(ddd_imports.extract({ "import com.acme.infrastructure.Db;", "import static org.x.Y.z;" }, "java")),
  { "org.x.Y.z", "com.acme.infrastructure.Db" }
)
eq(
  "Rust imports",
  specs(ddd_imports.extract({ "use crate::infrastructure::db;" }, "rs")),
  { "crate::infrastructure::db" }
)
eq("framework: recognises the package and does not confuse substrings", {
  ddd_imports.framework("database/sql", "go"),
  ddd_imports.framework("example.com/notes/sqlutil", "go"),
  ddd_imports.framework("express", "ts"),
  ddd_imports.framework("./expressions", "ts"),
}, { "database/sql", nil, "express", nil })
eq("layers by directory / import", {
  ddd_layers.of "internal/domain/order/order.go",
  ddd_layers.of "x/Infrastructure/db",
  ddd_layers.of "src/api/routes.ts",
  ddd_layers.of "util/strings.go",
}, { "domain", "infrastructure", "interface", nil })
eq("the dependency rule points inward", {
  ddd_layers.ALLOWED.domain.infrastructure,
  ddd_layers.ALLOWED.infrastructure.domain,
  ddd_layers.ALLOWED.application.interface,
}, { nil, true, nil })
eq("composition root and tests", {
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

write("util/helpers.go", { "package util", "", "type Helper struct{}" }) -- outside every layer: not even read
local idx
ddd_index.reset()
ddd_index.get(proj, function(i)
  idx = i
end)
vim.wait(5000, function()
  return idx ~= nil
end, 20)
eq(
  "index: files, layers and types",
  { #idx.list, idx.counts.domain, idx.counts.application, idx.counts.infrastructure },
  { 7, 4, 1, 1 }
)
eq("index: what is not in a layer is not read, but is counted", { idx.files["util/helpers.go"], idx.seen }, { nil, 8 })
local viol = ddd_rules.violations(idx)
local kinds = {}
for _, v in ipairs(viol) do
  kinds[#kinds + 1] = v.rule .. "@" .. v.file
end
eq("violations: domain→infrastructure, framework and name (and NOT the composition root)", kinds, {
  "framework@domain/order/order.go",
  "dependency@domain/order/order.go",
  "naming@domain/order/misnamed.go",
})
eq("domain violation is ERROR", viol[1].severity, vim.diagnostic.severity.ERROR)
local aggs = ddd_rules.aggregates(idx)
local by_agg = {}
for _, a in ipairs(aggs) do
  by_agg[a.name] = a
end
eq("aggregates: Order complete, Note without port", {
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
  eq("wiring: the implementation only lives in its own file → not wired", by_agg.Order.wired, false)
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
  eq("wiring: referenced from cmd/main.go → wired", by_agg.Order.wired, true)
end
local naming = ddd_naming.profile(idx)
eq(
  "inferred naming: snake_case and repository role",
  { naming.style, naming.roles[1] and naming.roles[1].name },
  { "snake", "repository" }
)
eq("file suggestion in the project's style", {
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
eq("what is missing: Note port with the project's file name, and use case", {
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
eq("<ddd> section: layer, allowed dependencies, convention, related piece and violations", {
  section:find("layer: domain (may depend on: domain)", 1, true) ~= nil,
  section:find("files: snake_case", 1, true) ~= nil,
  section:find("Order: port OrderRepository", 1, true) ~= nil,
  section:find("violation line 5", 1, true) ~= nil,
  section:find("Go: constructor New<T>", 1, true) ~= nil,
}, { true, true, true, true, true })
eq("compact <ddd> section (< 1800 characters)", #section < 1800, true)
-- the full provider on a real buffer
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
eq("ddd provider: section with the file's layer", provided and provided:find("layer: domain", 1, true) ~= nil, true)
-- DDD actions: own registry, distinct names in the history, context with <ddd>
local ddd_actions = require "agent.ddd.actions"
eq(
  "DDD actions: separate names and all ask for <ddd>",
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

-- persistent findings: save, restore re-anchoring by line text, discard what no longer exists
local persist = require "agent.persist"
local ptmp = vim.fn.tempname() .. ".json"
persist.use(ptmp)
eq("re-anchor: the same line, shifted, or absent", {
  persist.reanchor({ "a", "b", "c" }, { line = 2, text = "b" }),
  persist.reanchor({ "x", "y", "a", "b", "c" }, { line = 2, text = "b" }),
  persist.reanchor({ "a", "c" }, { line = 2, text = "b" }),
}, { 2, 4, nil })
eq("re-anchor: two matches, the closest", persist.reanchor({ "}", "x", "}", "y", "}" }, { line = 4, text = "}" }), 3)

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
eq("persistence: saves 2 findings with their line text", persist.count(), 2)
-- "another session": without diagnostics, they are restored on open
vim.diagnostic.reset(fns, fbuf)
persist.restore(fbuf)
local back = vim.diagnostic.get(fbuf, { namespace = fns })
eq(
  "persistence: restores messages, severities and lines",
  { #back, back[1].message, back[1].lnum, back[2].source, back[2].severity },
  { 2, "A returns a magic number", 3, "ddd", vim.diagnostic.severity.INFO }
)
-- the code moved (3 new lines above): re-anchored by text
vim.diagnostic.reset(fns, fbuf)
vim.api.nvim_buf_set_lines(fbuf, 0, 0, false, { "// l1", "// l2", "// l3" })
persist.restore(fbuf)
back = vim.diagnostic.get(fbuf, { namespace = fns })
table.sort(back, function(a, b)
  return a.lnum < b.lnum
end)
eq(
  "persistence: after shifting the code, they are re-anchored (lines 6 and 10)",
  { #back, back[1].lnum, back[2].lnum },
  { 2, 6, 10 }
)
-- a rewritten line: that finding is discarded, the other one stays
vim.diagnostic.reset(fns, fbuf)
vim.api.nvim_buf_set_lines(fbuf, 6, 7, false, { "\treturn computeA()" })
persist.restore(fbuf)
back = vim.diagnostic.get(fbuf, { namespace = fns })
eq(
  "persistence: what was rewritten is discarded and removed from what is saved",
  { #back, back[1].message, persist.count() },
  { 1, "B returns a magic number", 1 }
)
-- the `findings` provider sees it; `review` and `ddd review` do not (they must not start from what the previous review said)
local findings_provider = require "agent.context.providers.findings"
local fout
findings_provider.collect({ buf = fbuf, first = 9, last = 12 }, function(t)
  fout = t or ""
end)
eq(
  "findings provider: line, severity, source, message and code",
  fout,
  "L11 INFO[ddd]: B returns a magic number | return 2"
)
eq("review and ddd review do NOT read earlier findings", {
  vim.tbl_contains(actions.get("review").context, "findings"),
  vim.tbl_contains(require("agent.ddd.actions").get("review").context, "findings"),
}, { false, false })
eq("fix and ddd fix DO read them", {
  vim.tbl_contains(actions.get("fix").context, "findings"),
  vim.tbl_contains(require("agent.ddd.actions").get("fix").context, "findings"),
}, { true, true })
-- resolve a rewritten range
require("agent.output.findings").resolve(fbuf, 9, 12)
eq(
  "resolve: the rewritten range is left without findings, also in what is saved",
  { #vim.diagnostic.get(fbuf, { namespace = fns }), persist.count() },
  { 0, 0 }
)

-- clear: one at a time (line / selection), per file and all
local agent_api = require "agent"
local dns = require("agent.ddd.diagnose").namespace()
vim.api.nvim_set_current_buf(fbuf)
local function seed()
  vim.diagnostic.set(fns, fbuf, {
    { lnum = 3, col = 0, message = "A", severity = vim.diagnostic.severity.WARN, source = "agent" },
    { lnum = 7, col = 0, message = "B", severity = vim.diagnostic.severity.INFO, source = "agent" },
  })
  vim.diagnostic.set(dns, fbuf, { { lnum = 7, col = 0, message = "C", severity = 2, source = "ddd" } })
  persist.sync(fbuf, "findings")
  persist.sync(fbuf, "ddd")
end
local function left()
  return #vim.diagnostic.get(fbuf, { namespace = fns }) + #vim.diagnostic.get(fbuf, { namespace = dns })
end
seed()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
agent_api.clear "line" -- no finding on that line: touches nothing
eq("clear line: with no finding on the line it removes nothing", { left(), persist.count() }, { 3, 3 })
vim.api.nvim_win_set_cursor(0, { 4, 0 })
agent_api.clear "line"
eq("clear line: removes only the one on that line (memory and disk)", { left(), persist.count() }, { 2, 2 })
agent_api.clear("line", 7, 9) -- selection: review and ddd of that range
eq("clear selection: removes review and ddd from the range", { left(), persist.count() }, { 0, 0 })
seed()
agent_api.clear "file"
eq("clear file: removes everything in the file", { left(), persist.count() }, { 0, 0 })
seed()
agent_api.clear "all"
eq("clear all: removes everything, also what is saved", { left(), persist.count() }, { 0, 0 })
seed()
vim.api.nvim_win_set_cursor(0, { 8, 0 })
vim.cmd "AgentClear"
eq("command :AgentClear: the cursor line", left(), 1)
vim.cmd "AgentClear file"
eq("command :AgentClear file", left(), 0)
seed()
vim.cmd "AgentClear all"
eq("command :AgentClear all", { left(), persist.count() }, { 0, 0 })
-- the fix check: without diagnostics there is nothing to fix
local ddd_fix = require("agent.ddd.actions").get "fix"
eq("ddd fix: with nothing to attend to it says so", ddd_fix.check { buf = fbuf, first = 1, last = 12 } ~= nil, true)
vim.diagnostic.set(fns, fbuf, { { lnum = 9, col = 0, message = "x", severity = 2, source = "ddd" } })
eq("ddd fix: with a finding in the range, it proceeds", ddd_fix.check { buf = fbuf, first = 8, last = 12 }, nil)
-- ddd: the project's diagnosis is saved per file and `forget_all` clears it
persist.replace_all(
  "ddd",
  { [ffile] = { { line = 5, severity = 1, message = "domain imports infra", source = "ddd" } } }
)
eq("ddd persistence: saved with the line text", persist.count(), 1)
persist.forget_all "ddd"
eq("forget_all clears a key in all files", persist.count(), 0)
vim.diagnostic.reset(fns, fbuf)
vim.fn.delete(ffile)
vim.fn.delete(ptmp)
persist.use(nil)

-- regression: the agent UI defines its colors WITHOUT going through the `agent` facade (the DDD menu does not load it;
-- without this, if DDD was the first thing you used, block, title and panels came out flat white)
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
    "colors: '" .. mod .. "' defines the agent groups on its own",
    { t.fg ~= nil, i.fg ~= nil and i.bg ~= nil },
    { true, true }
  )
end
require("agent.ui.highlights").ensure()

-- CONTRACTS: the port an adapter implements, what it lacks, a sibling example and its table schema
local cnames = require "agent.repository.contracts.names"
local ccontracts = require "agent.repository.contracts"
local cdiscovery = require "agent.discovery"
local cschema = require "agent.repository.contracts.schema"
eq("names: from the adapter to the port and the entity", {
  cnames.candidates "PostgresOrderRepository",
  cnames.candidates "OrderRepositoryImpl",
  cnames.candidates "pgOrderRepository",
  cnames.entity_of "PostgresOrderRepository",
  cnames.entity_of "InMemoryNoteStore",
  cnames.looks_like_implementation "OrderService",
}, { { "OrderRepository" }, { "OrderRepository" }, { "OrderRepository" }, "Order", "Note", false })
eq(
  "names: plural table first (order is a reserved word)",
  { cnames.tables "OrderItem", cnames.tables "Category", cnames.tables "Address" },
  { { "order_items", "order_item" }, { "categories", "category" }, { "addresses", "address" } }
)
eq("port methods: Go, TypeScript, Python and Rust", {
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
  "scope type: from a Go method it resolves to its receiver's struct",
  { ctarget.kind, ctarget.name, ctarget.first },
  { "class", "PostgresOrderRepository", 5 }
)
local subject = ccontracts.subject(ctarget)
eq("target subject", subject, "PostgresOrderRepository")
-- with the cursor ON the Go struct the name lives in `type_spec`: the target must carry it anyway
local _, on_struct = open_target("internal/infrastructure/postgres/order_repository.go", 5, "type")
eq(
  "cursor on `type X struct`: the target carries its name",
  { on_struct.kind, on_struct.name },
  { "class", "PostgresOrderRepository" }
)
open_target("internal/infrastructure/postgres/order_repository.go", 7, "type")
eq("explicit ports: Go, TS, Python and Rust", {
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
    "port found by name, with its methods",
    { port and port.name, port and port.methods },
    { "OrderRepository", { "Save", "ByID", "Delete" } }
  )
  local implemented, ctor = ccontracts.implemented(ctarget, "PostgresOrderRepository", "go")
  eq(
    "implemented: Save yes, ByID and Delete no; no constructor",
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
  eq("sibling: another implementation, with the missing method and its constructor", {
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
  eq("schema: the entity's CREATE TABLE and the later changes", {
    created:find("total_cents bigint", 1, true) ~= nil,
    found and #found.changes,
    found and found.changes[1]:find("ADD COLUMN notes", 1, true) ~= nil,
  }, { true, 2, true })
  local env = cschema.environment(cp, "go", created, { "database/sql" })
  eq(
    "environment: postgres (by syntax) with pgx and database/sql, numbered parameters",
    { env.dialect, env.driver, env.access[1], env.line:find("$1, $2", 1, true) ~= nil },
    { "postgres", "pgx", "database/sql", true }
  )
  eq(
    "agnostic environment: MySQL by its syntax → `?`",
    cschema
      .environment(cp, "go", "CREATE TABLE t (id INT AUTO_INCREMENT) ENGINE=InnoDB;", {}).line
      :find("? (positional)", 1, true) ~= nil,
    true
  )
  eq("without schema or driver, no dialect is made up", cschema.environment("/nonexistent", "go", nil, {}).dialect, nil)

  -- the full providers
  local out
  require("agent.context.providers.contracts").collect(ctarget, function(t)
    out = t or ""
  end, { names = {}, action = { examples = true } })
  vim.wait(5000, function()
    return out ~= nil
  end, 20)
  eq("contracts provider: port, missing ones and example (with paths)", {
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
  eq("without `examples`, the example is not paid for", no_example:find("example method", 1, true), nil)
  eq("contracts brings the entity the port names (and its fields), even if the target does not mention it", {
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
  eq("schema provider: dialect, real table and changes", {
    sch:find("db: postgres", 1, true) ~= nil,
    sch:find("CREATE TABLE orders", 1, true) ~= nil,
    sch:find("later changes:", 1, true) ~= nil,
  }, { true, true, true })
  -- silent if it is not an adapter
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
  eq("a service gets neither port nor schema (cost 0)", { c2, s2 }, { "", "" })
end
vim.fn.delete(cp, "rf")

-- architecture LEVELS: repository (<leader>aP) and service (<leader>aS), each with its own folder, registry and menu
local repo_check = require "agent.repository.check"
eq("repository check: columns of a CREATE TABLE and entity fields (ignoring case and underscores)", {
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
eq("service: by name or by living in the application layer", {
  service_ports.looks_like_service("PlaceOrderService", "x.go"),
  service_ports.looks_like_service("PlaceOrder", "internal/application/place.go"),
  service_ports.looks_like_service("PostgresOrderRepository", "internal/infrastructure/x.go"),
}, { true, true, false })
eq("service: the field that holds the port, in Go, TS, Python and Java", {
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
  "deps: calls FindAll, which the port does not declare",
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
  eq("service: finds the ports it receives (fields and constructor) with their methods", {
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
  eq("ports provider: each port with its path and 'call only these methods'", {
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
  eq("implementations of a port by name", { #impls, impls[1] and impls[1].name }, { 1, "PostgresOrderRepository" })
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
  eq("referenced_elsewhere: nobody uses it outside its own file", used, false)
  -- a handler/other function receives no ports
  local fb = with_buffer("go", { "package x", "", "func Helper() {", "}" }, 3)
  local ftgt = assert(target_mod.resolve(fb, "function", nil))
  local fout
  require("agent.context.providers.ports").collect(ftgt, function(t)
    fout = t or ""
  end, { names = {}, action = {} })
  vim.wait(2000, function()
    return fout ~= nil
  end, 20)
  eq("an arbitrary function receives no ports (cost 0)", fout, "")
end
vim.fn.delete(sp, "rf")
-- registries and menus per level
local repo_actions, service_actions = require "agent.repository.actions", require "agent.service.actions"
eq("actions per level: own names and full contract", {
  vim.tbl_map(function(a)
    return a.name
  end, repo_actions.list()),
  vim.tbl_map(function(a)
    return a.name
  end, service_actions.list()),
}, { { "repo_port", "repo_implement", "repo_review" }, { "service_implement", "service_review" } })
for _, a in ipairs(vim.list_extend(vim.list_extend({}, repo_actions.list()), service_actions.list())) do
  eq(
    "action '" .. a.name .. "' meets the contract",
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
eq("main menu without `port` (it lives in its level)", vim.tbl_contains(main_keys, "p"), false)
eq(
  "Repository menu (<leader>aP): port, implement, review, check",
  { require("menus.agent_repository").prefix, keys_of(require "menus.agent_repository") },
  { "aP", { "p", "i", "r", "c" } }
)
eq(
  "Service menu (<leader>aS): implement, review, deps",
  { require("menus.agent_service").prefix, keys_of(require "menus.agent_service") },
  { "aS", { "i", "r", "d" } }
)
local prefixes = {}
for _, ctx in ipairs(require("menus").contexts()) do
  prefixes[#prefixes + 1] = ctx.prefix
end
eq(
  "the three levels are registered as leader groups",
  { vim.tbl_contains(prefixes, "aD"), vim.tbl_contains(prefixes, "aP"), vim.tbl_contains(prefixes, "aS") },
  { true, true, true }
)
eq(
  "the `port` action is no longer in the main registry",
  pcall(function()
    return require("agent.actions").get "port"
  end),
  false
)

-- action registry: minimum contract
for _, a in ipairs(require("agent.actions").list()) do
  local ok = a.label and a.desc and a.key and (a.handler or (a.output and a.system and a.task))
  eq("action '" .. a.name .. "' meets the contract", ok and true or false, true)
end
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
