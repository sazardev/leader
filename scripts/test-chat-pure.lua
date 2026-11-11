-- Pure and rendering tests for the chat (<leader>aC).
-- Runs headless with the real config (plugins available) but touches no network:
-- triggers, files, commands, input history/height, mention parsing, every
-- rendering shape a model can produce, and the copy helpers.
local fails, total = 0, 0

local function eq(name, got, want)
  total = total + 1
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print(("FAIL %s\n  got:  %s\n  want: %s"):format(name, vim.inspect(got), vim.inspect(want)))
  end
end

local function ok(name, cond, extra)
  eq(name .. (cond and "" or ("  " .. tostring(extra or ""))), cond and true or false, true)
end

local function group(title)
  print("\n── " .. title .. " ──")
end

local root = vim.fn.getcwd()

-- ── trigger ──────────────────────────────────────────────────────────────────
group("trigger")
local trigger = require("agent.chat.trigger")

local kind, q, sc = trigger.detect("/mo", 3)
eq("command: kind", kind, "command")
eq("command: query", q, "mo")
eq("command: start", sc, 0)
kind, q, sc = trigger.detect("   /new ", 7)
eq("command: leading spaces", { kind, q, sc }, { "command", "new", 3 })
eq("command: mid text is not a command", trigger.detect("hola /mo", 8), nil)
eq("command: inside a word is not a command", trigger.detect("a/b", 3), nil)

kind, q, sc = trigger.detect("lee @nvim/lua", 13)
eq("file: after text", { kind, q, sc }, { "file", "nvim/lua", 4 })
kind, q = trigger.detect("@", 1)
eq("file: bare @", { kind, q }, { "file", "" })
eq("file: after a word char does not trigger", trigger.detect("foo@bar", 7), nil)
kind = trigger.detect("(@n", 3)
eq("file: after opening punctuation", kind, "file")
kind, q = trigger.detect("mira #cave", 10)
eq("skill: trigger", { kind, q }, { "skill", "cave" })
kind = trigger.detect("usa " .. string.char(36) .. "open", 9)
eq("mcp: trigger", kind, "mcp")

local _, _, start_col, end_col = trigger.detect("/model", 3)
eq("token end: cursor mid command", { start_col, end_col }, { 0, 6 })
eq("replace: whole token", { trigger.replace("/model", 0, 6, "") }, { "", 0 })
eq(
  "replace: keeps what follows",
  { trigger.replace("hola @nvim/x tail", 5, 12, "@nvim/x ") },
  { "hola @nvim/x  tail", 13 }
)
eq("replace: cursor after insert", ({ trigger.replace("lee @a", 4, 6, "@abc ") })[2], 9)
eq("signs", { trigger.sign("command"), trigger.sign("file") }, { "/", "@" })

-- ── commands ────────────────────────────────────────────────────────────────
group("commands")
local commands = require("agent.chat.commands")
eq("filter: prefix", commands.filter("mo"), { "model" })
eq("filter: empty lists all, in order", commands.filter("")[1], "new")
ok("filter: case insensitive", #commands.filter("M") >= 1)
eq("has", { commands.has("new"), commands.has("nope") }, { true, false })
eq("has: profile/history", { commands.has("profile"), commands.has("history") }, { true, true })
eq("candidates: value+desc", (commands.candidates("he"))[1], { value = "help", desc = "help" })

-- ── profiles ────────────────────────────────────────────────────────────────
group("profiles")
local profiles = require("agent.chat.profiles")
eq("profiles: order", profiles.ORDER, { "ask", "write", "minimal" })
eq(
  "profiles: labels",
  { profiles.label("ask"), profiles.label("write"), profiles.label("minimal") },
  { "Ask", "Write", "Minimal" }
)
eq("profiles: unknown falls back to write", profiles.get("nope").id, "write")
eq("profiles: cycle wraps", profiles.cycle("minimal", 1), "ask")
eq("profiles: cycle backwards", profiles.cycle("ask", -1), "minimal")
ok("profiles: ask is read-only by prompt", profiles.get("ask").system:find("read%-only") ~= nil)
ok("profiles: write has the full context", profiles.get("write").context.buffer and profiles.get("write").context.mcp)
ok("profiles: minimal injects no automatic context", profiles.get("minimal").context.buffer == false)
eq("profiles: minimal context collector is empty", #require("agent.chat.context").collect(profiles.get("minimal")), 0)
eq("profiles: session fallback", profiles.of({}, "ask").id, "ask")

-- ── files.filter ────────────────────────────────────────────────────────────
group("files")
local files = require("agent.chat.files")
local sample = { "a/b/c.lua", "src/chat.lua", "src/cache.lua", "README.md", "docs/x.md" }
eq("filter: empty takes the head", files.filter(sample, "", 2), { "a/b/c.lua", "src/chat.lua" })
eq("filter: exact prefix wins", files.filter(sample, "src/ch")[1], "src/chat.lua")
eq("filter: substring", files.filter(sample, "chat")[1], "src/chat.lua")
eq("filter: subsequence", files.filter(sample, "rme")[1], "README.md")
eq("filter: no match", #files.filter(sample, "zzzz"), 0)
ok("filter: limit", #files.filter(sample, "", 1) == 1)
ok("files.list returns project files", #files.list() > 10, #files.list())
ok("files.resolve finds a project file", files.resolve("nvim/init.lua") ~= nil)

-- ── input (history + height) ────────────────────────────────────────────────
group("input")
local input = require("agent.chat.input")
local list = { "uno", "dos" }
local text, state = input.step({ idx = 0, draft = "" }, list, -1, "borrador")
eq(
  "history: first up returns the newest and stores the draft",
  { text, state.idx, state.draft },
  { "dos", 1, "borrador" }
)
text, state = input.step(state, list, -1, "lo escrito")
eq("history: second up goes older", { text, state.idx }, { "uno", 2 })
text, state = input.step(state, list, -1, "")
eq("history: clamps at the oldest", { text, state.idx }, { "uno", 2 })
text, state = input.step(state, list, 1, "")
eq("history: down returns newer", { text, state.idx }, { "dos", 1 })
text, state = input.step(state, list, 1, "")
eq("history: down again returns the draft", { text, state.idx }, { "borrador", 0 })
text = input.step({ idx = 0, draft = "" }, {}, -1, "x")
eq("history: no messages keeps the draft", text, "x")

eq("height: one short line", input.height({ "hola" }, 40, 5), 1)
eq("height: wraps a long line", input.height({ string.rep("a", 200) }, 40, 10), 5)
eq("height: CJK counts double width", input.height({ string.rep("你", 30) }, 40, 10), 2)
eq("height: clamps to max", input.height({ "a", "b", "c" }, 40, 2), 2)
eq("height: empty is 1", input.height({ "" }, 40, 5), 1)

-- ── layout (geometry is pure) ───────────────────────────────────────────────
group("layout")
local layout = require("agent.chat.layout")
local cfg = { width = 0.5, rail_width = 9, input_height = 5, gap = 0 }
local w, col, top, th, ih, full = layout.geometry(cfg, 160, 48, false, "mini", 3)
eq("half: half the columns", w, 80)
eq("half: not full", full, false)
eq("half: content flush to the right edge", { col + w, top }, { 160, 0 })
eq("half: input height follows content", ih, 3)
eq("half: transcript fills the usable height", th, 48 - 1 - 3)
ok("half: blocks fill every usable row", th + ih == 48 - 1, { th, ih })
local fw, fcol, frow, fth, fih, isfull = layout.geometry(cfg, 160, 48, false, "full", 5)
eq("full: every column", fw, 160)
eq("full: origin", { fcol, frow, isfull }, { 0, 0, true })
ok("full: leaves the statusline row", fth + fih <= 48 - 1, { fth, fih })
ok("full: transcript takes the rest", fth > 30, fth)
eq("collapsed: rail width", layout.geometry(cfg, 160, 48, true, "mini", 3), 9)
eq("collapsed: rail flush right", select(2, layout.geometry(cfg, 160, 48, true, "mini", 3)), 151)
local narrow = layout.geometry(cfg, 50, 20, false, "mini", 2)
ok("narrow: panel still fits", narrow >= 28 and narrow <= 50, narrow)
eq("small rows: still flush to the top", select(3, layout.geometry(cfg, 80, 20, false, "mini", 2)), 0)

-- ── text ────────────────────────────────────────────────────────────────────
group("text")
local chat_text = require("agent.chat.text")
eq("text: CRLF normalizes", chat_text.normalize("a\r\nb\rc"), "a\nb\nc")
eq("text: ANSI escapes go", chat_text.strip_ansi("a\27[31mred\27[0m b"), "ared b")
eq("text: clean does both", chat_text.clean("x\r\n\27[1mY\27[0m"), "x\nY")
eq("text: trim", chat_text.trim("  x  "), "x")
ok("text: clip cuts", chat_text.clip(string.rep("a", 100), 10):find("…") ~= nil)
eq("text: tokens", chat_text.tokens(1234), "1.2k")

-- ── mention parsing ─────────────────────────────────────────────────────────
group("mention")
local mention = require("agent.chat.mention")
local clean, sections, slash = mention.parse("hola mundo")
eq("mention: plain text", { clean, #sections, slash }, { "hola mundo", 0, nil })
clean, sections, slash = mention.parse("/model foo")
eq("mention: slash and rest", { clean, slash }, { "foo", "model" })
clean, sections, slash = mention.parse("/nope")
eq("mention: unknown slash is text", { clean, slash }, { "/nope", nil })
clean, sections = mention.parse("revisa @nvim/init.lua porfa")
eq("mention: @file adds one section", #sections, 1)
ok("mention: @file names the path", sections[1].name:find("nvim/init.lua", 1, true) ~= nil, sections[1].name)
ok("mention: @file carries content", #sections[1].text > 0)
clean, sections = mention.parse("lee @does/not/exist")
eq("mention: missing file adds nothing", #sections, 0)
eq("mention: text is kept", clean, "lee @does/not/exist")

-- @buf reads the current buffer
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "linea uno", "linea dos" })
local _, secs = mention.parse("mira @buf")
eq("mention: @buf", #secs, 1)
ok("mention: @buf content", secs[1].text:find("linea uno", 1, true) ~= nil)
-- @diag reads diagnostics
local ns = vim.api.nvim_create_namespace("chat.test")
vim.diagnostic.set(ns, 0, { { lnum = 0, col = 0, message = "boom", severity = vim.diagnostic.severity.ERROR } })
local _, dsecs = mention.parse("arregla @diag")
eq("mention: @diag", #dsecs, 1)
ok("mention: @diag content", dsecs[1].text:find("boom", 1, true) ~= nil)
vim.diagnostic.reset(ns, 0)
-- #skill (stubbed store)
package.loaded["skills.store"] = {
  body = function(id)
    return "SKILL " .. id
  end,
}
local _, ssecs = mention.parse("#caveman y #flutter")
eq("mention: two skills", #ssecs, 2)
eq("mention: skill body", ssecs[1].text, "SKILL caveman")
package.loaded["skills.store"] = nil

-- ── ask blocks: a question with options the picker answers ───────────────────
group("ask")
local ask = require "agent.chat.ask"
local a1 = ask.parse "hola\n\n```ask\nWhich database?\n- PostgreSQL\n- SQLite\n```\n"
eq("ask: question", a1 and a1.question, "Which database?")
eq("ask: options", a1 and a1.options, { "PostgreSQL", "SQLite" })
eq("ask: no block", ask.parse "hola", nil)
eq("ask: no options is not a question", ask.parse "```ask\nonly a question\n```", nil)
eq("ask: unclosed block", ask.parse "```ask\nQ\n- one", nil)
local a2 = ask.parse "```ask\nOld?\n- a\n- b\n```\n\n```ask\nNew?\n1. one\n2) two\n```"
eq("ask: the last block wins", { a2.question, a2.options }, { "New?", { "one", "two" } })
local ask_s = require("agent.chat.session").new { root = root }
require("agent.chat.session").add(ask_s, { role = "assistant", text = "```ask\nQ?\n- a\n- b\n```" })
eq("ask: of reads the last answer", ask.of(ask_s).question, "Q?")
eq("ask: of a plain answer", ask.of(require("agent.chat.session").new { root = root }), nil)

-- ── @need: context the model requests ────────────────────────────────────────
group("needs")
local needs = require "agent.chat.needs"
eq(
  "needs: parse comma/space lists without repeats",
  needs.parse "x\n@need: nvim/init.lua, README.md\n@need: nvim/init.lua",
  { "nvim/init.lua", "README.md" }
)
eq("needs: no line", needs.parse "hola", {})
local need_s = require("agent.chat.session").new { root = root }
require("agent.chat.session").add(need_s, { role = "assistant", text = "I need it.\n@need: nvim/init.lua" })
local need_secs = needs.collect(need_s)
eq("needs: injects the requested file", #need_secs, 1)
ok("needs: names it like a mention", need_secs[1].name:find("file:", 1, true) == 1, need_secs[1].name)
ok("needs: carries content", #need_secs[1].text > 0)
needs.mark(need_s)
eq("needs: a request is used once", #needs.collect(need_s), 0)
local outside_s = require("agent.chat.session").new { root = root }
require("agent.chat.session").add(outside_s, { role = "assistant", text = "@need: /etc/passwd" })
eq("needs: outside the project is ignored", #needs.collect(outside_s), 0)
require("core.settings").agent.chat.auto_need = false
local off_s = require("agent.chat.session").new { root = root }
require("agent.chat.session").add(off_s, { role = "assistant", text = "@need: nvim/init.lua" })
eq("needs: setting turns it off", #needs.collect(off_s), 0)
require("core.settings").agent.chat.auto_need = true

-- ── history budget: what was left out is known ──────────────────────────────
group("history")
local hist = require("agent.chat.session").new { root = root }
require("agent.chat.session").add(hist, { role = "user", text = string.rep("a", 40) })
require("agent.chat.session").add(hist, { role = "assistant", text = string.rep("b", 40) })
require("agent.chat.session").add(hist, { role = "user", text = "nuevo" })
local kept, dropped = require("agent.chat.session").history(hist, 10)
eq("history: newest turn kept", { #kept, kept[1].text }, { 1, "nuevo" })
eq("history: dropped chars", dropped, 80)
local big = require("agent.chat.session").new { root = root }
require("agent.chat.session").add(big, { role = "assistant", text = string.rep("x", 13000) })
require("agent.chat.session").add(big, { role = "user", text = "new" })
local big_system, _, _, big_dropped = require("agent.chat.prompt").build(big, "hi", {}, profiles.get "minimal")
eq("history: prompt reports what it dropped", big_dropped, 13000)
ok("history: minimal budget is the tight one", big_system:find("Minimal mode", 1, true) ~= nil)

-- ── rendering: every shape a model can produce ──────────────────────────────
group("render")
local render = require("agent.chat.render")
local session = require("agent.chat.session").new({ root = root, backend = "chatfake", model = "m" })
local add = require("agent.chat.session").add

local function blocks_of(s)
  return render.lines(s, {})
end

-- plain text
add(session, { role = "user", text = "hola" })
add(session, { role = "assistant", text = "Hola, ¿en qué te ayudo?" })
local lines, marks, ranges = blocks_of(session)
local plain = table.concat(lines, "\n")
ok("render: user line clean (no icon)", plain:find("\nhola\n", 1, true) ~= nil)
ok("render: assistant line clean (no icon)", plain:find("\nHola, ¿en qué te ayudo?\n", 1, true) ~= nil)
eq("render: ranges for both messages", #ranges, 2)
ok("render: range holds its message", ranges[1].msg.role == "user" and ranges[2].msg.role == "assistant")
ok("render: ranges do not overlap", ranges[1].last < ranges[2].first, { ranges[1].last, ranges[2].first })

-- an empty chat teaches the commands instead of leaving the block blank
local fresh = require("agent.chat.session").new({ root = root, backend = "chatfake", model = "m" })
local wl = table.concat(render.lines(fresh, {}), "\n")
ok("render: empty chat lists commands", wl:find("COMMANDS", 1, true) ~= nil and wl:find("/help", 1, true) ~= nil)
ok("render: empty chat lists mentions", wl:find("@file", 1, true) ~= nil and wl:find("#skill", 1, true) ~= nil)
ok("render: empty chat lists keys", wl:find("Shift-Enter", 1, true) ~= nil and wl:find("Ctrl-Q", 1, true) ~= nil)
ok("render: welcome has no brand icons", not wl:find("◆", 1, true) and not wl:find("✦", 1, true))

-- markdown as is
local md = table.concat({
  "## Título",
  "",
  "- uno",
  "- dos",
  "",
  "> cita",
  "",
  "```lua",
  "print('hola')",
  "```",
  "",
  "Inline `code` y un enlace [x](https://e.com).",
}, "\n")
add(session, { role = "assistant", text = md })
lines = blocks_of(session)
local body = table.concat(lines, "\n")
ok("render: heading kept at column 0", body:find("\n## Título", 1, true) ~= nil)
ok("render: list kept", body:find("\n- uno", 1, true) ~= nil)
ok("render: quote kept", body:find("\n> cita", 1, true) ~= nil)
ok("render: fence at column 0", body:find("\n```lua", 1, true) ~= nil)
ok(
  "render: a message starting with a fence keeps its markdown (no prefix)",
  body:find("\n```lua", 1, true) ~= nil and body:find("✦ ", 1, true) == nil
)
ok("render: code line untouched", body:find("\nprint('hola')", 1, true) ~= nil)
ok("render: closing fence", body:find("\n```\n", 1, true) ~= nil or body:find("\n```$") ~= nil)
ok("render: inline code kept", body:find("Inline `code`", 1, true) ~= nil)

-- a `lang: path` fence is display-only metadata: the transcript must keep a
-- parser-friendly language or treesitter cannot highlight the code block
local defs = require("agent.chat.session").new({ root = root, backend = "chatfake", model = "m" })
require("agent.chat.session").add(defs, { role = "assistant", text = "```go: main.go\npackage main\n```" })
local dtext = table.concat(render.lines(defs, {}), "\n")
ok("render: path is not the code language", dtext:find("\n```go\n", 1, true) ~= nil and dtext:find("```go: main.go", 1, true) == nil)
eq("render: copy keeps the path", render.message_text(defs.messages[1]), "```go: main.go\npackage main\n```")
local shell = require("agent.chat.session").new({ root = root, backend = "chatfake", model = "m" })
require("agent.chat.session").add(shell, { role = "assistant", text = "```\ngo run main.go\n```" })
local stext = table.concat(render.lines(shell, {}), "\n")
ok("render: unlabeled terminal block gets bash", stext:find("\n```bash\n", 1, true) ~= nil)
eq("render: copy keeps the bare fence", render.message_text(shell.messages[1]), "```\ngo run main.go\n```")

-- copy is exact (no icons, no indentation added)
local copy = render.message_text(session.messages[#session.messages])
eq("copy: markdown message byte for byte", copy, md)
local code = render.code_block_at(session.messages[#session.messages], 8)
eq("copy: code block without fences", code, "print('hola')")
eq("copy: outside a fence is nil", render.code_block_at(session.messages[#session.messages], 1), nil)

-- an ask block is a quote, not code, and points at the picker
local asks = require("agent.chat.session").new { root = root }
require("agent.chat.session").add(asks, { role = "assistant", text = "```ask\nWhich?\n- one\n- two\n```" })
local atext = table.concat(render.lines(asks, {}), "\n")
ok("render: ask content is a quote", atext:find("> Which?", 1, true) ~= nil)
ok("render: ask fence hidden", atext:find("```ask", 1, true) == nil)
ok("render: ask hint", atext:find("Alt-Q", 1, true) ~= nil)
-- history trim is disclosed in the turn footer
require("agent.chat.session").add(asks, { role = "assistant", text = "ok", meta = { history_dropped = 1234 } })
ok(
  "render: history trim footer",
  table.concat(render.lines(asks, {}), "\n"):find("history: oldest 1.2k chars not sent", 1, true) ~= nil
)

-- CRLF + ANSI + tabs
add(session, { role = "assistant", text = "linea1\r\nlinea2\r\n\27[31mrojo\27[0m\r\n\tta\tb" })
lines = blocks_of(session)
local all = table.concat(lines, "\n")
ok("render: no CR", not all:find("\r"), all:gsub("\r", "<CR>"))
ok("render: ANSI stripped", not all:find("\27"), "escape left")
ok("render: tab kept", (all:find("\tta\tb", 1, true)) ~= nil)
eq(
  "copy: tabs and LF normalized",
  render.message_text(session.messages[#session.messages]),
  "linea1\nlinea2\nrojo\n\tta\tb"
)

-- wide chars and emoji
add(session, { role = "assistant", text = "日本語のテキスト 🚀 emoji 👩‍💻 y acentos: ñandú" })
lines = blocks_of(session)
all = table.concat(lines, "\n")
ok("render: wide text kept", all:find("日本語", 1, true) ~= nil)
ok("render: emoji kept", all:find("🚀", 1, true) ~= nil)
eq(
  "copy: wide text",
  render.message_text(session.messages[#session.messages]),
  "日本語のテキスト 🚀 emoji 👩‍💻 y acentos: ñandú"
)

-- multi-line user message: every line clean, no prefix
add(session, { role = "user", text = "primera\nsegunda\n\ncuarta" })
lines = blocks_of(session)
local joined = table.concat(lines, "\n")
ok("render: multiline user starts clean", joined:find("\nprimera\n", 1, true) ~= nil)
ok("render: multiline user second line raw", joined:find("\nsegunda", 1, true) ~= nil)
ok("render: blank line kept", joined:find("segunda\n\ncuarta", 1, true) ~= nil)
eq("copy: multiline user", render.message_text(session.messages[#session.messages]), "primera\nsegunda\n\ncuarta")

-- thinking, tool, context
add(session, { role = "thinking", text = "pienso" })
add(session, { role = "tool", text = "error de red" })
add(session, { role = "context", text = "x" })
lines = blocks_of(session)
all = table.concat(lines, "\n")
ok("render: thinking clean", all:find("\npienso\n", 1, true) ~= nil)
ok("render: tool error clean", all:find("\nerror de red\n", 1, true) ~= nil)
local hidden = render.lines(session, { show_thinking = false, show_context = false })
ok("render: thinking can be hidden", not table.concat(hidden, "\n"):find("pienso", 1, true))
add(session, {
  role = "assistant",
  text = "ok",
  meta = { injected = { "rules", "git" }, usage = { tokens_in = 1200, tokens_out = 30, cost = 0.001, ms = 1500 } },
})
lines = blocks_of(session)
all = table.concat(lines, "\n")
ok("render: injected footer", all:find("injected rules,git", 1, true) ~= nil)
ok("render: usage footer", all:find("1.2k/30 tok", 1, true) ~= nil)
ok("render: cost", all:find("$0.0010", 1, true) ~= nil)
ok("render: time", all:find("1s", 1, true) ~= nil)
local no_tokens = render.lines(session, { show_tokens = false })
ok("render: tokens can be hidden", not table.concat(no_tokens, "\n"):find("tok", 1, true))

-- streaming pending, rail
local pending = render.lines(session, { pending = "escribiendo", thinking = "pensando" })
all = table.concat(pending, "\n")
ok("render: pending stream clean", all:find("\nescribiendo", 1, true) ~= nil and all:find("✦", 1, true) == nil)
ok("render: streaming thinking clean", all:find("\npensando\n", 1, true) ~= nil)
local rail = render.lines(session, { rail = true, running = true })
ok("render: rail", table.concat(rail, ""):find("CHAT", 1, true) ~= nil)

-- empty message and long line
add(session, { role = "assistant", text = "" })
lines = blocks_of(session)
ok("render: empty message is one line", lines[#lines - 1] ~= nil)
add(session, { role = "assistant", text = string.rep("a", 10000) })
lines = blocks_of(session)
ok("render: long line kept whole", table.concat(lines, "\n"):find(string.rep("a", 10000), 1, true) ~= nil)
eq("copy: long line exact", #render.message_text(session.messages[#session.messages]), 10000)

-- control characters, RTL, combining marks, nested fences, blank output
add(session, { role = "assistant", text = "a\0b\7c\nválido\tfin" })
lines = blocks_of(session)
all = table.concat(lines, "\n")
ok("render: NUL and bell removed", not all:find("%z") and not all:find("\7"))
ok("render: tab and newline kept", all:find("válido\tfin", 1, true) ~= nil)
add(session, { role = "assistant", text = "مرحبا بالعالم e\204\129 (combinado)" })
ok("render: RTL and combining marks kept", table.concat(blocks_of(session), "\n"):find("مرحبا", 1, true) ~= nil)
add(session, { role = "assistant", text = "````md\n```lua\nx\n```\n````" })
ok("render: nested fences kept", table.concat(blocks_of(session), "\n"):find("````md", 1, true) ~= nil)
add(session, { role = "assistant", text = "\n\n   \n" })
ok("render: whitespace-only message does not crash", #blocks_of(session) > 0)
add(session, { role = "assistant", text = "```\n```" })
eq("copy: empty code block", render.code_block_at(session.messages[#session.messages], 1), nil)

-- trigger with a unicode prefix (byte columns)
local uni = "😀 @nv"
local k, q2b, scb = trigger.detect(uni, #uni)
eq("trigger: unicode prefix", { k, q2b, scb }, { "file", "nv", 5 })

-- height: mixed multiline + wrapping
local mixed = { string.rep("x", 90), "corta", string.rep("y", 45) }
eq("height: mixed lines", input.height(mixed, 40, 10), 3 + 1 + 2)

-- ── history home ────────────────────────────────────────────────────────────
group("home")
local home = require("agent.chat.home")
local now = 1700000000
eq("home: age now", home.relative_time(now - 5, now), "now")
eq("home: age minutes", home.relative_time(now - 120, now), "2m")
eq("home: age hours", home.relative_time(now - 7200, now), "2h")
eq("home: age days", home.relative_time(now - 3 * 86400, now), "3d")
eq("home: title strips markdown", home.title("## `fix` the **thing**"), "fix the **thing**")
local hs = {
  {
    id = "a",
    title = "## Fix the repo",
    updated = now - 120,
    messages = { {}, {} },
    backend = "claude",
    model = "haiku",
  },
  { id = "b", title = "Second", updated = now - 7200, messages = {}, backend = "opencode", model = "flash" },
}
local hh = { sessions = hs, root = "/tmp/x", display_root = "~/x", sel = 2, profile = "ask" }
local hlines, hmarks, hranges = home.lines(hh, { now = now })
local htext = table.concat(hlines, "\n")
ok("home: brand", htext:find("Leader Chat", 1, true) ~= nil)
ok("home: project and profile", htext:find("~/x · 2 chats · Ask", 1, true) ~= nil)
ok("home: new chat row", htext:find("  New chat", 1, true) ~= nil)
ok("home: session title cleaned", htext:find("  Fix the repo", 1, true) ~= nil)
ok("home: commands explained", htext:find("COMMANDS", 1, true) ~= nil and htext:find("/help", 1, true) ~= nil)
ok("home: keys explained", htext:find("KEYS", 1, true) ~= nil and htext:find("Ctrl-Q", 1, true) ~= nil)
ok("home: no brand icons", not htext:find("◆", 1, true) and not htext:find("✚", 1, true) and not htext:find("❯", 1, true))
ok("home: session meta", htext:find("2m · 2 messages · claude/haiku", 1, true) ~= nil)
eq("home: one range for new + one per session", #hranges, 3)
eq("home: selected row is the second session", hh.sel, 2)
eq("home: row at line", home.row_at(hranges, hranges[3].first), 3)
local function mark_at(marks, line)
  for _, m in ipairs(marks) do
    if m.line == line then
      return m
    end
  end
end
local selected = mark_at(hmarks, hranges[2].first)
ok("home: selected row painted", selected and selected.hl == "ChatHomeSel")
ok("home: selected row is a full-width bar", selected and selected.eol == true)
local hempty = { sessions = {}, root = "/tmp/y", display_root = "~/y", sel = 1, profile = "minimal" }
ok("home: empty state", table.concat(home.lines(hempty, { now = now }), "\n"):find("No chats", 1, true) ~= nil)

-- markdown header carries the profile and the brand
local hp = render.lines(session, { profile = "ask" })
local hpt = table.concat(hp, "\n")
ok("render: brand header", hpt:find("Leader Chat", 1, true) ~= nil)
ok("render: profile in header", hpt:find("Ask · ", 1, true) ~= nil)
ok("render: write profile by default", table.concat(render.lines(session, {}), "\n"):find("Write · ", 1, true) ~= nil)

-- prompt uses the selected profile
local ask_system, ask_prompt = require("agent.chat.prompt").build(session, "hi", {}, profiles.get("ask"))
ok("prompt: ask role", ask_system:find("Ask mode", 1, true) ~= nil)
ok("prompt: ask closing instruction", ask_prompt:find("Read%-only") ~= nil)
ok(
  "prompt: every profile teaches the ask and @need rules",
  ask_system:find("fenced `ask`", 1, true) ~= nil and ask_system:find("@need:", 1, true) ~= nil
)
local min_system = require("agent.chat.prompt").build(session, "hi", {}, profiles.get("minimal"))
ok("prompt: minimal role", min_system:find("Minimal mode", 1, true) ~= nil)

-- ── apply: Write answers that carry full files ───────────────────────────────
group("apply")
local apply = require "agent.chat.apply"
local ab = apply.blocks "```go: main.go\npackage main\n\nfunc main() {}\n```\n"
eq("apply: one block", #ab, 1)
eq("apply: path", ab[1].path, "main.go")
eq("apply: body", ab[1].body, { "package main", "", "func main() {}" })
eq("apply: a snippet without path is not a file", #apply.blocks "```go\nfmt.Println()\n```\n", 0)
eq("apply: a bare path as info", apply.blocks("```main.go\npackage main\n```\n")[1].path, "main.go")
local aroot = vim.fn.tempname()
vim.fn.mkdir(aroot, "p")
vim.fn.writefile({ "package main" }, aroot .. "/main.go")
local ares = apply.run({ root = aroot }, "```go: main.go\n--- a/main.go\n+++ b/main.go\n```\n")
eq("apply: a diff is skipped", { #ares.files, #ares.skipped }, { 0, 1 })
ares = apply.run({ root = aroot }, "```go: main.go\npackage main\n\nfunc main() {}\n```\n")
eq("apply: written", { #ares.files, ares.files[1] }, { 1, "main.go" })
eq("apply: disk", vim.fn.readfile(aroot .. "/main.go"), { "package main", "", "func main() {}" })
ares = apply.run({ root = aroot }, "```go: main.go\npackage main\n\nfunc main() {}\n```\n")
eq("apply: unchanged", #ares.unchanged, 1)
vim.fn.writefile({ "old" }, aroot .. "/note.txt")
vim.cmd("edit " .. vim.fn.fnameescape(aroot .. "/note.txt"))
ares = apply.run({ root = aroot }, "```text: note.txt\nnew\n```\n")
eq("apply: loaded buffer is written", { #ares.files, vim.fn.readfile(aroot .. "/note.txt") }, { 1, { "new" } })
eq("apply: loaded buffer content", vim.api.nvim_buf_get_lines(0, 0, -1, false), { "new" })
vim.api.nvim_buf_delete(0, { force = true })
ares = apply.run({ root = aroot }, "```text: ../escape.txt\nx\n```\n")
eq("apply: outside the project is skipped", #ares.skipped, 1)
ares = apply.run({ root = aroot }, "```text: new.txt\nx\n```\n")
eq("apply: a new file is skipped", #ares.skipped, 1)
vim.fn.delete(aroot, "rf")

group("fuzz")
math.randomseed(7)
local alphabet = {
  "a",
  "Z",
  "0",
  " ",
  "\n",
  "\t",
  "@",
  "#",
  "$",
  "/",
  "`",
  "```",
  ">",
  "-",
  "*",
  "😀",
  "日",
  "😀‍💻",
  "\27[31m",
  "\27[0m",
  "\r",
  "\0",
  "ñ",
  "[",
  "]",
  "(",
  ")",
  "é",
}
local function random_text()
  local n = math.random(0, 60)
  local out = {}
  for i = 1, n do
    out[i] = alphabet[math.random(#alphabet)]
  end
  return table.concat(out)
end
local fuzz_ok, fuzz_err = true, nil
for i = 1, 200 do
  local t = random_text()
  local s2 = require("agent.chat.session").new({ root = root, backend = "chatfake", model = "m" })
  local ok_add = pcall(function()
    add(s2, { role = "user", text = t })
    add(s2, { role = "assistant", text = t })
    add(s2, { role = "thinking", text = t })
  end)
  local ok_render = pcall(function()
    local l, m, rg = render.blocks(s2, {})
    assert(type(l) == "table" and #l > 0)
    assert(#rg == 3)
    for _, r in ipairs(rg) do
      assert(r.first >= 1 and r.last >= r.first and r.last <= #l)
    end
  end)
  if not (ok_add and ok_render) then
    fuzz_ok = false
    fuzz_err = ("case %d: %s"):format(i, vim.inspect(t))
    break
  end
  local clean = render.message_text(s2.messages[2])
  if clean:find("\0") or clean:find("\27") or clean:find("\r") then
    fuzz_ok = false
    fuzz_err = ("case %d left control chars: %s"):format(i, vim.inspect(clean))
    break
  end
  -- triggers must never throw on random lines/cursors
  local line = (t:gsub("\n", " "))
  local ok_trig = pcall(function()
    for c = 0, #line do
      local kind, _, sc, ec = trigger.detect(line, c)
      if kind and sc and ec then
        trigger.replace(line, sc, ec, "@x ")
      end
    end
  end)
  if not ok_trig then
    fuzz_ok = false
    fuzz_err = ("trigger case %d: %s"):format(i, vim.inspect(line))
    break
  end
end
ok("fuzz: 200 random texts render and copy cleanly", fuzz_ok, fuzz_err)

-- ── window-level copy (code block and message) ──────────────────────────────
group("window copy")
local window = require("agent.chat.window")
local s = require("agent.chat.session").new({ root = root, backend = "chatfake", model = "m" })
require("agent.chat.session").add(s, { role = "assistant", text = "```lua\nlocal x = 1\n```" })
window.session = s
window.toggle()
window.draw()
vim.api.nvim_set_current_win(window.transcript_win)
local r = window.ranges[1]
vim.api.nvim_win_set_cursor(window.transcript_win, { r.first + 1, 0 }) -- inside the fence
eq(
  "copy: code block under the cursor",
  { window.copy_code_block(), vim.fn.getreg(string.char(34)) },
  { true, "local x = 1" }
)
vim.api.nvim_win_set_cursor(window.transcript_win, { r.first, 0 })
eq(
  "copy: message under the cursor",
  { window.copy_message(), vim.fn.getreg(string.char(34)) },
  { true, "```lua\nlocal x = 1\n```" }
)
window.hide()

print(("\n%d checks, %d failed"):format(total, fails))
if fails > 0 then
  vim.cmd("cq 1")
end
