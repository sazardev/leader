-- Pruebas del panel de commit (lua/commit): análisis Conventional Commits, lecturas/acciones de git sobre un repo
-- temporal, y el panel entero (lista, preparar/quitar, borrador de IA con un backend falso, commit y amend).
-- Hermético: repo en un directorio temporal, estado del agente en memoria, sin red ni tokens.
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

vim.o.columns, vim.o.lines = 130, 40
local conv = require "commit.conventional"

-- ── Conventional Commits (puro) ──────────────────────────────────────────────
eq(
  "split: tipo, scope, ruptura y asunto",
  conv.split "feat(api)!: add x",
  { type = "feat", scope = "api", breaking = true, subject = "add x" }
)
eq("split: sin scope", conv.split "fix: bug", { type = "fix", scope = nil, breaking = false, subject = "bug" })
eq("split: falta el espacio tras los dos puntos", conv.split "fix:bug", nil)
eq("split: no es conventional", conv.split "Update stuff", nil)
eq("parse_header: válido", (conv.parse_header "feat(commit): panel nuevo").scope, "commit")
eq("parse_header: tipo desconocido", select(2, conv.parse_header "wip: algo"), "unknown type `wip`")
eq("parse_header: asunto vacío", select(2, conv.parse_header "feat: ") ~= nil, true)
eq(
  "parse_header: demasiado largo",
  select(2, conv.parse_header("feat: " .. ("x"):rep(80))):find("max 72", 1, true) ~= nil,
  true
)
eq("check: vacío", conv.check("").state, "empty")
eq("check: tipo sin asunto", conv.check("feat(x): ").state, "incomplete")
eq(
  "check: ok",
  { conv.check("fix(ui): arregla el borde").state, conv.check("fix(ui): arregla el borde").len },
  { "ok", 25 }
)
eq("check: error de tipo", conv.check("nope: x").state, "error")
eq(
  "rewrite: cambia el tipo y conserva scope y asunto",
  conv.rewrite("feat(ui): borde", { type = "fix" }),
  "fix(ui): borde"
)
eq("rewrite: cambia el scope", conv.rewrite("feat(ui): borde", { scope = "core" }), "feat(core): borde")
eq("rewrite: quita el scope", conv.rewrite("feat(ui): borde", { scope = false }), "feat: borde")
eq("rewrite: plantilla desde cero", conv.rewrite("", { type = "docs" }), "docs: ")
eq("suggest_type: solo docs", conv.suggest_type { "README.md", "docs/a.md" }, "docs")
eq("suggest_type: mezcla → nil", conv.suggest_type { "README.md", "src/a.go" }, nil)
eq(
  "history_scopes: del más al menos usado",
  conv.history_scopes "feat(a): x\nfix(b): y\nfeat(a): z\nchore: q",
  { "a", "b" }
)
eq("clean_message: sin vallas ni comillas", conv.clean_message "```\nfeat: x\n```", { "feat: x" })

-- ── repo temporal ────────────────────────────────────────────────────────────
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local function sh(...)
  local res = vim.system(vim.list_extend({ "git" }, { ... }), { cwd = repo, text = true }):wait()
  return vim.trim(res.stdout or "")
end
local function write(name, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(repo .. "/" .. name, ":h"), "p")
  vim.fn.writefile(lines, repo .. "/" .. name)
end
sh("init", "-q", "-b", "main")
sh("config", "user.email", "t@t")
sh("config", "user.name", "t")
sh("config", "commit.gpgsign", "false")
write("a.lua", { "one", "two" })
write("b.lua", { "x" })
sh("add", "-A")
sh("commit", "-q", "-m", "chore: base")
write("a.lua", { "one", "TWO", "three" }) -- se preparará
write("b.lua", { "x", "y" }) -- quedará sin preparar
write("docs/c.md", { "nuevo" }) -- sin seguimiento
sh("add", "a.lua")

local git = require "commit.git"
local entries = git.status(repo)
eq(
  "status: preparado primero, luego sin preparar, luego nuevo",
  vim.tbl_map(function(e)
    return e.path .. ":" .. e.letter .. ":" .. tostring(e.staged)
  end, entries),
  { "a.lua:M:true", "b.lua:M:false", "docs/:?:false" }
)
eq("status: +/− de lo preparado", { entries[1].adds, entries[1].dels }, { 2, 1 })
eq("status: +/− de lo no preparado", { entries[2].adds, entries[2].dels }, { 1, 0 })
eq("branch: sin upstream", { git.branch(repo).name, git.branch(repo).upstream }, { "main", nil })
git.stage(repo, { "b.lua" })
eq("stage: b.lua pasa a preparado", git.status(repo)[2].staged, true)
git.unstage(repo, { "b.lua" })
eq("unstage: vuelve a no preparado", git.status(repo)[2].staged, false)
write("a.lua", { "one", "TWO", "three", "four" })
eq("status: preparado con más cambios sin preparar = parcial", git.status(repo)[1].partial, true)
sh("add", "a.lua")

-- ── el panel ─────────────────────────────────────────────────────────────────
local notes = {}
vim.notify = function(msg, level)
  notes[#notes + 1] = { msg = msg, level = level }
end
local function last_note()
  return notes[#notes] and notes[#notes].msg or ""
end

-- backend falso para el borrador (estado en memoria: no toca tu agent.json)
local state = require "agent.state"
local real_get, real_set = state.get, state.set
local store = { backend = "fakecommit" }
state.get = function(k)
  return store[k]
end
state.set = function(k, v)
  store[k] = v
end
local FAKE = { cmd = { "printf", "%s", "feat(editor): add the commit panel\n\n- shows what is committed" } }
require("agent.backends").register("fakecommit", {
  name = "fakecommit",
  label = "Fake",
  available = function()
    return true
  end,
  models = function(cb)
    cb {}
  end,
  build = function(req)
    FAKE.req = req
    return { cmd = FAKE.cmd, cwd = vim.fn.tempname():match "^(.*)/" or "/tmp" }
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

vim.cmd("cd " .. vim.fn.fnameescape(repo))
local panel = require "commit.panel"

local function wins_open()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      n = n + 1
    end
  end
  return n
end
local function float_bufs()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      out[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = vim.api.nvim_win_get_buf(w)
    end
  end
  return out
end
local function title_of(buf)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      local t = vim.api.nvim_win_get_config(w).title
      local parts = {}
      for _, c in ipairs(type(t) == "table" and t or {}) do
        parts[#parts + 1] = c[1]
      end
      return table.concat(parts)
    end
  end
end
local function press(buf, lhs, mode)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode or "n")) do
    local function key(x)
      return vim.api.nvim_replace_termcodes(x, true, true, true):lower()
    end
    if key(m.lhs) == key(lhs) then
      return m.callback()
    end
  end
  error("no mapping " .. lhs)
end
local function wait(cond, ms)
  return vim.wait(ms or 5000, cond, 25)
end

panel.open()
local fb = float_bufs()
eq("panel: tres flotantes (archivos, mensaje y línea del agente)", wins_open(), 3)
local lines = vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)
eq(
  "panel: cabecera de lo que SÍ se commitea",
  lines[1]:find("Staged · 1 file — goes in the commit", 1, true) ~= nil,
  true
)
eq("panel: cabecera de lo que NO se commitea", lines[3]:find("Not staged · 2 — NOT included", 1, true) ~= nil, true)
eq("panel: filas de archivo con marca y letra", {
  lines[2]:find("● M", 1, true) ~= nil,
  lines[4]:find("○ M", 1, true) ~= nil,
  lines[5]:find("○ ?", 1, true) ~= nil,
}, { true, true, true })
eq("panel: título con la rama", title_of(fb.commitfiles):find("main", 1, true) ~= nil, true)
eq("panel: con algo preparado el foco va al mensaje", vim.bo[vim.api.nvim_get_current_buf()].filetype, "gitcommit")
eq(
  "panel: mensaje vacío → título con el formato esperado",
  title_of(fb.gitcommit):find("type(scope): subject", 1, true) ~= nil,
  true
)

-- línea del agente: anuncia qué leerá y con qué modelo ANTES de gastar nada
local function ai_text()
  return vim.api.nvim_buf_get_lines(fb.commitstatus, 0, 1, false)[1] or ""
end
local before = ai_text()
eq("panel: el agente anuncia modelo y archivos que leerá", {
  before:find("fakecommit", 1, true) ~= nil,
  before:find("reads 1 file", 1, true) ~= nil,
  before:find("⌃g to draft", 1, true) ~= nil,
}, { true, true, true })

-- preparar desde la lista
vim.api.nvim_set_current_win(vim.fn.bufwinid(fb.commitfiles))
vim.api.nvim_win_set_cursor(0, { 4, 0 })
press(fb.commitfiles, "<Space>")
lines = vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)
eq("panel: ⎵ prepara el archivo bajo el cursor", lines[1]:find("Staged · 2 files", 1, true) ~= nil, true)
eq("panel: tras preparar, el anuncio de la IA cuenta 2 archivos", ai_text():find("reads 2 files", 1, true) ~= nil, true)
press(fb.commitfiles, "u")
eq(
  "panel: u quita todo de lo preparado",
  vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)[1]:find("Staged · 0 files", 1, true) ~= nil,
  true
)
eq(
  "panel: sin nada preparado la lista lo explica",
  vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)[2]:find("nothing staged yet", 1, true) ~= nil,
  true
)
press(fb.commitfiles, "a")
eq(
  "panel: a lo prepara todo",
  vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)[1]:find("Staged · 3 files", 1, true) ~= nil,
  true
)
press(fb.commitfiles, "u")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press(fb.commitfiles, "a")
press(fb.commitfiles, "u")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
git.stage(repo, { "a.lua" })
panel.close()
eq("panel: close cierra las dos ventanas", wins_open(), 0)

-- borrador de IA
panel.open { ai = true }
fb = float_bufs()
eq(
  "panel: <leader>Gm arranca el borrador",
  wait(function()
    return ai_text():find("drafted by", 1, true) ~= nil
  end),
  true
)
eq(
  "IA: el mensaje del agente llena la ventana",
  vim.api.nvim_buf_get_lines(fb.gitcommit, 0, -1, false),
  { "feat(editor): add the commit panel", "", "- shows what is committed" }
)
eq(
  "IA: el título valida el borrador (✔ tipo(scope) y largo)",
  title_of(fb.gitcommit):find("✔ feat(editor)", 1, true) ~= nil,
  true
)
eq(
  "IA: tras el borrador se ve modelo, tokens y coste",
  { ai_text():find("100→20 tok", 1, true) ~= nil, ai_text():find("$0.0004", 1, true) ~= nil },
  { true, true }
)
eq("IA: lo enviado incluye el diff preparado y la lista de tipos", {
  FAKE.req.prompt:find("<diff>", 1, true) ~= nil,
  FAKE.req.prompt:find("TWO", 1, true) ~= nil,
  FAKE.req.system:find("feat, fix", 1, true) ~= nil,
}, { true, true, true })
eq(
  "IA: el borrador usa el nivel ligero (commit)",
  require("agent.selection").current({ name = "commit", tier = "light" }).tier,
  "light"
)

-- tipo y scope desde el panel
local picks = { { "fix" }, { "ui" } }
local real_select = vim.ui.select
vim.ui.select = function(items, opts, cb)
  local want = table.remove(picks, 1)[1]
  for i, it in ipairs(items) do
    if it == want or (type(it) == "table" and it[1] == want) then
      return cb(it, i)
    end
  end
  cb(nil)
end
press(fb.gitcommit, "<C-t>")
eq(
  "tipo: ⌃t cambia el tipo y conserva el resto",
  vim.api.nvim_buf_get_lines(fb.gitcommit, 0, 1, false)[1],
  "fix(editor): add the commit panel"
)
vim.ui.select = real_select

-- commit
eq("antes de commitear HEAD es el commit base", sh("log", "-1", "--format=%s"), "chore: base")
vim.cmd "stopinsert"
press(fb.gitcommit, "<C-s>", "n")
eq(
  "commit: el commit se hace y se cierra el panel",
  wait(function()
    return wins_open() == 0
  end),
  true
)
eq("commit: asunto del commit", sh("log", "-1", "--format=%s"), "fix(editor): add the commit panel")
eq("commit: el cuerpo viaja", sh("log", "-1", "--format=%b"), "- shows what is committed")
eq("commit: solo lo preparado (b.lua y docs/ quedan fuera)", sh("show", "--name-only", "--format=", "HEAD"), "a.lua")
eq(
  "commit: aviso con hash, archivos y +/−",
  last_note():find("Committed", 1, true) ~= nil and last_note():find("1 file +", 1, true) ~= nil,
  true
)

-- validaciones: asunto inválido y nada preparado NO commitean
git.stage(repo, { "b.lua" })
panel.open()
fb = float_bufs()
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, -1, false, { "wip: nope" })
press(fb.gitcommit, "<C-s>")
eq(
  "validación: un tipo desconocido no commitea",
  { sh("log", "-1", "--format=%s"), last_note():find("unknown type", 1, true) ~= nil },
  { "fix(editor): add the commit panel", true }
)
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, -1, false, { "feat(x): ok" })
press(fb.gitcommit, "<C-s>")
eq(
  "commit 2: b.lua",
  wait(function()
    return sh("log", "-1", "--format=%s") == "feat(x): ok" and wins_open() == 0
  end),
  true
)

-- IA con error: el panel lo muestra y sigue usable
write("a.lua", { "again" })
sh("add", "a.lua")
FAKE.cmd = { "sh", "-c", "exit 3" }
panel.open { ai = true }
fb = float_bufs()
eq(
  "IA con error: se anuncia en la línea del agente",
  wait(function()
    return ai_text():find("AI failed", 1, true) ~= nil
  end),
  true
)
eq(
  "IA con error: el mensaje sigue vacío y el panel abierto",
  { vim.api.nvim_buf_get_lines(fb.gitcommit, 0, -1, false), wins_open() },
  { { "" }, 3 }
)
panel.close()

-- sin nada preparado
sh("reset", "-q")
panel.open()
fb = float_bufs()
eq("sin nada preparado: foco en la lista", vim.bo[vim.api.nvim_get_current_buf()].filetype, "commitfiles")
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, -1, false, { "feat(x): sin nada" })
press(fb.gitcommit, "<C-s>")
eq(
  "sin nada preparado: no commitea y avisa",
  { sh("log", "-1", "--format=%s"), last_note():find("Nothing staged", 1, true) ~= nil },
  { "feat(x): ok", true }
)
panel.close()

-- amend: el mensaje del último commit llega precargado
require("commit").amend()
fb = float_bufs()
eq(
  "amend: mensaje precargado y título",
  { vim.api.nvim_buf_get_lines(fb.gitcommit, 0, 1, false)[1], title_of(fb.commitfiles):find("Amend", 1, true) ~= nil },
  { "feat(x): ok", true }
)
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, 1, false, { "feat(x): ok again" })
press(fb.gitcommit, "<C-s>")
eq(
  "amend: reescribe el último commit",
  wait(function()
    return sh("log", "-1", "--format=%s") == "feat(x): ok again" and wins_open() == 0
  end),
  true
)
eq("amend: no crea un commit nuevo", sh("rev-list", "--count", "HEAD"), "3")

-- árbol limpio
sh("reset", "-q", "--hard")
sh("clean", "-fdq")
panel.open()
eq("árbol limpio: no abre nada", { wins_open(), last_note():find("Nothing to commit", 1, true) ~= nil }, { 0, true })

state.get, state.set = real_get, real_set
vim.fn.delete(repo, "rf")
print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
