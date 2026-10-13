-- ── Commits con Conventional Commits (menú <leader>G) ────────────────────────
--   <leader>Gc  asistente: tipo → scope → asunto → ventana de mensaje (cuerpo opcional)
--   <leader>Gm  mensaje redactado por la IA a partir del diff preparado (se revisa antes)
--   <leader>Ga  reescribe el mensaje del último commit (avisa si ya está en el remoto)
-- Los tipos y límites viven en settings.git.commit; el hook .githooks/commit-msg valida lo
-- mismo al hacer `git commit` desde cualquier sitio. Los scopes se sugieren desde las rutas
-- preparadas y desde los scopes que ya usa el historial del repo.
local log = require "utils.log"
local text = require "agent.text"

local M = {}

local function cfg()
  return require("core.settings").git.commit
end

-- directorios que no dicen nada como scope
local GENERIC = {
  nvim = true,
  lua = true,
  src = true,
  lib = true,
  app = true,
  pkg = true,
  internal = true,
  cmd = true,
  plugins = true,
  utils = true,
  core = true,
}

---@param args string[]
---@param root string
---@param stdin string?
---@return string stdout, integer code, string stderr
local function git(args, root, stdin)
  local res = vim.system(vim.list_extend({ "git" }, args), { cwd = root, text = true, stdin = stdin }):wait()
  return vim.trim(res.stdout or ""), res.code, res.stderr or ""
end

---@return string?
local function repo_root()
  local name = vim.api.nvim_buf_get_name(0)
  local root = vim.fs.root(name ~= "" and 0 or vim.uv.cwd(), ".git")
  if not root then
    log.warn "Not inside a git repository"
  end
  return root
end

---@param root string
---@return string[]
local function staged(root)
  local out = git({ "diff", "--cached", "--name-only" }, root)
  return out == "" and {} or vim.split(out, "\n", { plain = true })
end

-- ── análisis puro (sin UI; lo único que merece prueba) ───────────────────────

--- Valida la primera línea: `tipo(scope)!: asunto`, tipo de la lista, largo máximo
---@param line string
---@return { type: string, scope: string?, breaking: boolean, subject: string }?, string? err
function M.parse_header(line)
  local type_, scope, bang, subject = line:match "^(%l+)%(([^()]+)%)(!?): (.+)$"
  if not type_ then
    type_, bang, subject = line:match "^(%l+)(!?): (.+)$"
  end
  if not type_ then
    return nil, "the first line must look like `type(scope): subject`"
  end
  local known = false
  for _, t in ipairs(cfg().types) do
    known = known or t[1] == type_
  end
  if not known then
    return nil, ("unknown type `%s`"):format(type_)
  end
  if #line > cfg().subject_max then
    return nil, ("the first line has %d characters (max %d)"):format(#line, cfg().subject_max)
  end
  return { type = type_, scope = scope, breaking = bang == "!", subject = subject }
end

--- Tipo probable según lo que se commitea (nil = sin pista)
---@param files string[]
---@return string?
function M.suggest_type(files)
  if #files == 0 then
    return nil
  end
  local function all(pred)
    for _, f in ipairs(files) do
      if not pred(f) then
        return false
      end
    end
    return true
  end
  if all(function(f)
    return f:match "^docs/" or f:match "%.md$" or f:match "%.txt$"
  end) then
    return "docs"
  end
  if all(function(f)
    return f:match "^tests?/" or f:match "_test%." or f:match "%.test%." or f:match "%.spec%."
  end) then
    return "test"
  end
  if all(function(f)
    return f:match "^%.github/" or f:match "Jenkinsfile" or f:match "%.gitlab%-ci"
  end) then
    return "ci"
  end
  if all(function(f)
    return f:match "lock" or f:match "go%.sum$" or f:match "go%.mod$" or f:match "package%.json$"
  end) then
    return "chore"
  end
  return nil
end

--- Scopes que ya usa el historial, del más al menos frecuente
---@param root string
---@return string[]
local function history_scopes(root)
  local out = git({ "log", "-n", tostring(cfg().history), "--format=%s" }, root)
  local counts = {}
  for line in out:gmatch "[^\n]+" do
    local scope = line:match "^%l+%(([^()]+)%)!?:"
    if scope then
      counts[scope] = (counts[scope] or 0) + 1
    end
  end
  local list = vim.tbl_keys(counts)
  table.sort(list, function(a, b)
    return counts[a] ~= counts[b] and counts[a] > counts[b] or a < b
  end)
  return list
end

--- Scopes sugeridos: primero los que salen de las rutas Y ya están en el historial, luego los
--- de las rutas, luego los más usados del historial
---@param files string[]
---@param history string[]
---@return string[]
function M.suggest_scopes(files, history)
  local counts = {}
  local function add(scope)
    scope = (scope or ""):gsub("^%.", ""):lower()
    if scope ~= "" and not GENERIC[scope] then
      counts[scope] = (counts[scope] or 0) + 1
    end
  end
  for _, f in ipairs(files) do
    local parts = vim.split(f, "/", { plain = true })
    local name = table.remove(parts):gsub("%..*$", "")
    for _, dir in ipairs(parts) do
      if not GENERIC[dir] then
        add(dir)
        break
      end
    end
    add(name)
  end

  local rank = {}
  for i, scope in ipairs(history) do
    rank[scope] = i
  end
  local from_paths = vim.tbl_keys(counts)
  table.sort(from_paths, function(a, b)
    if (rank[a] ~= nil) ~= (rank[b] ~= nil) then
      return rank[a] ~= nil
    end
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return (rank[a] or 0) < (rank[b] or 0) or a < b
  end)

  local result, seen = {}, {}
  for _, scope in ipairs(vim.list_extend(from_paths, vim.list_slice(history, 1, 8))) do
    if not seen[scope] and #result < 12 then
      seen[scope] = true
      result[#result + 1] = scope
    end
  end
  return result
end

-- ── ventana de mensaje ───────────────────────────────────────────────────────

---@param root string
---@param lines string[]
---@param opts { title: string, amend: boolean? }
local function open_editor(root, lines, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "commit-message-" .. buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "gitcommit"

  local width = math.min(84, vim.o.columns - 6)
  local height = math.max(8, math.min(20, #lines + 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
    title_pos = "center",
    footer = " <CR> / <C-s> commit · q cancel · body goes below the first line ",
    footer_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].colorcolumn = tostring(cfg().subject_max + 1)

  local busy = false
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    if busy then
      return
    end
    local kept = vim.tbl_filter(function(l)
      return not l:match "^#"
    end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local msg = vim.trim(table.concat(kept, "\n"))
    local _, err = M.parse_header(vim.split(msg, "\n", { plain = true })[1])
    if err then
      return log.warn("Commit message: " .. err)
    end

    busy = true
    log.info(opts.amend and "Amending… (hooks may take a few seconds)" or "Committing… (hooks may take a few seconds)")
    local cmd = { "git", "commit", "-F", "-" }
    if opts.amend then
      table.insert(cmd, 3, "--amend")
    end
    vim.system(cmd, { cwd = root, text = true, stdin = msg .. "\n" }, function(res)
      vim.schedule(function()
        busy = false
        if res.code ~= 0 then
          -- la ventana sigue abierta: se corrige el mensaje y se reintenta
          return log.error("git commit failed:\n" .. text.clip((res.stderr or "") .. (res.stdout or ""), 600))
        end
        close()
        vim.cmd "silent! checktime"
        pcall(function()
          require("gitsigns").refresh()
        end)
        log.info("Committed: " .. vim.split(msg, "\n", { plain = true })[1])
      end)
    end)
  end

  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, desc = "Git commit message " .. lhs })
  end
  map("n", "<CR>", submit)
  map({ "n", "i" }, "<C-s>", submit)
  map("n", "q", close)
  map("n", "<Esc>", close)
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
      submit()
    end,
  })
end

-- ── asistente ────────────────────────────────────────────────────────────────

--- Si no hay nada preparado, ofrece preparar todo; `cb` recibe los archivos preparados
---@param root string
---@param cb fun(files: string[])
local function ensure_staged(root, cb)
  local files = staged(root)
  if #files > 0 then
    return cb(files)
  end
  if git({ "status", "--porcelain" }, root) == "" then
    return log.info "Nothing to commit: the working tree is clean"
  end
  vim.ui.select(
    { "Stage everything (git add -A, includes untracked files)", "Cancel" },
    { prompt = "Nothing is staged" },
    function(_, idx)
      if idx == 1 then
        local _, code, err = git({ "add", "-A" }, root)
        if code ~= 0 then
          return log.error("git add failed: " .. text.clip(err, 300))
        end
        cb(staged(root))
      end
    end
  )
end

---@param files string[]
---@param cb fun(type: string)
local function pick_type(files, cb)
  local hint = M.suggest_type(files)
  -- el tipo sugerido va primero; el resto conserva el orden de la lista
  local items = {}
  for _, t in ipairs(cfg().types) do
    table.insert(items, t[1] == hint and 1 or #items + 1, t)
  end
  vim.ui.select(items, {
    prompt = "Commit type",
    format_item = function(t)
      return ("%-9s %s%s"):format(t[1], t[2], t[1] == hint and "   ← suggested" or "")
    end,
  }, function(choice)
    if choice then
      cb(choice[1])
    end
  end)
end

---@param candidates string[]
---@param cb fun(scope: string?)
local function pick_scope(candidates, cb)
  local items = vim.list_extend({}, candidates)
  items[#items + 1] = "(no scope)"
  items[#items + 1] = "custom…"
  vim.ui.select(items, { prompt = "Scope" }, function(choice, idx)
    if not choice then
      return
    end
    if idx == #items then
      return vim.ui.input({ prompt = "Scope: " }, function(input)
        input = vim.trim(input or "")
        if input ~= "" then
          cb(input)
        end
      end)
    end
    cb(idx == #items - 1 and nil or choice)
  end)
end

---@param prefix string
---@param cb fun(subject: string)
---@param default string?
local function ask_subject(prefix, cb, default)
  vim.ui.input({ prompt = prefix, default = default }, function(input)
    input = vim.trim(input or ""):gsub("%.$", "")
    if input == "" then
      return
    end
    if #prefix + #input > cfg().subject_max then
      log.warn(("Subject too long: %d characters, max %d. Shorten it."):format(#prefix + #input, cfg().subject_max))
      return ask_subject(prefix, cb, input)
    end
    cb(input)
  end)
end

--- <leader>Gc: tipo → scope → asunto → ventana de mensaje
function M.wizard()
  local root = repo_root()
  if not root then
    return
  end
  ensure_staged(root, function(files)
    pick_type(files, function(type_)
      pick_scope(M.suggest_scopes(files, history_scopes(root)), function(scope)
        local prefix = ("%s%s: "):format(type_, scope and ("(" .. scope .. ")") or "")
        ask_subject(prefix, function(subject)
          open_editor(root, { prefix .. subject, "", "" }, { title = "Commit message" })
          -- cursor listo para el cuerpo (opcional): Esc y <CR> commitea tal cual
          vim.api.nvim_win_set_cursor(0, { 3, 0 })
          vim.cmd "startinsert"
        end)
      end)
    end)
  end)
end

--- <leader>Ga: reescribe el mensaje del último commit
function M.amend()
  local root = repo_root()
  if not root then
    return
  end
  local msg, code = git({ "log", "-1", "--format=%B" }, root)
  if code ~= 0 or msg == "" then
    return log.warn "There is no commit to amend"
  end
  local function edit()
    open_editor(root, vim.split(msg, "\n", { plain = true }), {
      title = "Amend last commit (staged changes are included)",
      amend = true,
    })
  end
  -- reescribir un commit que otros ya pueden tener rompe su historial
  if git({ "branch", "-r", "--contains", "HEAD" }, root) == "" then
    return edit()
  end
  vim.ui.select({ "Amend anyway (needs a force push later)", "Cancel" }, {
    prompt = "This commit is already on the remote",
  }, function(_, idx)
    if idx == 1 then
      edit()
    end
  end)
end

-- ── mensaje con IA ───────────────────────────────────────────────────────────

---@type vim.SystemObj?
local generating

---@param files string[]
---@param root string
---@return string system, string prompt
local function ai_prompt(files, root)
  local c = cfg()
  local types = vim.tbl_map(function(t)
    return t[1]
  end, c.types)
  local scopes = M.suggest_scopes(files, history_scopes(root))

  local system = table.concat({
    "You write git commit messages in the Conventional Commits format.",
    "Output ONLY the commit message: no commentary, no code fences, no quotes.",
    "Format: `type(scope): subject`, then optionally a blank line and a body.",
    "- type: one of " .. table.concat(types, ", ") .. ".",
    #scopes > 0 and ("- scope: a short lowercase noun for the area touched; prefer one of: %s. Omit it when the change is cross-cutting."):format(
      table.concat(scopes, ", ")
    ) or "- scope: a short lowercase noun for the area touched; omit it when the change is cross-cutting.",
    ("- subject: imperative, lowercase first letter, no trailing period; the whole first line at most %d characters."):format(
      c.subject_max
    ),
    "- body: only when the change needs the WHY; wrap at 72 columns; plain sentences or `- ` bullets.",
    "- Breaking change: `!` after the type/scope and a `BREAKING CHANGE:` footer.",
    "- Match the style of the recent commits shown.",
    "- Write the message in " .. c.language .. ". Keep identifiers, paths and the type in their original form.",
  }, "\n")

  local diff = git({ "diff", "--cached", "-U2", "--no-color", "--", ".", ":(exclude)*lock*", ":(exclude)*.sum" }, root)
  if #diff > c.diff_max_chars then
    diff = diff:sub(1, c.diff_max_chars) .. "\n[diff truncated]"
  end
  local prompt = table.concat({
    "<recent_commits>\n" .. git({ "log", "-n", "15", "--format=%s" }, root) .. "\n</recent_commits>",
    "<staged_files>\n" .. git({ "diff", "--cached", "--stat" }, root) .. "\n</staged_files>",
    "<diff>\n" .. diff .. "\n</diff>",
    "<task>\nWrite the commit message for the staged changes.\n</task>",
  }, "\n")
  return system, prompt
end

--- Quita vallas de código y comillas que algunos modelos añaden alrededor del mensaje
---@param out string
---@return string[]
function M.clean_message(out)
  local lines = vim.tbl_filter(function(l)
    return not l:match "^%s*```"
  end, vim.split(out, "\n", { plain = true }))
  local msg = vim.trim(table.concat(lines, "\n")):gsub("^[\"'`]+", ""):gsub("[\"'`]+$", "")
  return vim.split(msg, "\n", { plain = true })
end

--- <leader>Gm: la IA propone el mensaje; se abre la ventana para revisarlo antes de commitear
function M.ai()
  if generating then
    return log.info "A commit message is already being generated"
  end
  local root = repo_root()
  if not root then
    return
  end
  ensure_staged(root, function(files)
    local system, prompt = ai_prompt(files, root)
    log.info "Writing the commit message…"
    generating = require("agent").complete({ action = "commit", system = system, prompt = prompt }, function(ok, out)
      generating = nil
      if not ok then
        return log.error("Commit message: " .. text.clip(out, 400))
      end
      open_editor(root, M.clean_message(out), { title = "Commit message (AI) — review before committing" })
    end)
  end)
end

return M
