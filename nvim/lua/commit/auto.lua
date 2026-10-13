-- ── Commit automático (<leader>GM): sin panel, en segundo plano ──────────────
-- Qué hace, en este orden, y nada más:
--   1. si hay archivos preparados, commitea ESO; si no, prepara todo lo modificado (menos lo sensible: settings
--      git.commit.sensitive) y lo deja anotado para deshacerlo si algo falla;
--   2. pide UN mensaje al agente (commit/ai.lua: diff compacto, rama, asuntos recientes, tipos; todo en inglés);
--   3. valida la cabecera (Conventional Commits) y commitea;
--   4. avisa en una línea: hash, mensaje, archivos, +/− y lo que costó.
-- Si algo falla (sin backend, error de la IA, cabecera inválida, un hook), lo preparado por esta orden se
-- deshace y no queda nada a medias: el aviso dice qué pasó y cómo seguir a mano (<leader>Gm).
local conventional = require "commit.conventional"
local git = require "commit.git"
local log = require "utils.log"
local text = require "agent.text"

local M = {}

local busy = false

---@param path string
---@return boolean
local function sensitive(path)
  for _, p in ipairs(require("core.settings").git.commit.sensitive or {}) do
    if path:find(p) or vim.fs.basename(path):find(p) then
      return true
    end
  end
  return false
end

---@param entries CommitEntry[]
---@return integer adds, integer dels
local function totals(entries)
  local adds, dels = 0, 0
  for _, e in ipairs(entries) do
    adds, dels = adds + (e.adds or 0), dels + (e.dels or 0)
  end
  return adds, dels
end

function M.run()
  if busy then
    return log.info "Commit: an automatic commit is already running"
  end
  local root = git.root()
  if not root then
    return log.warn "Not inside a git repository"
  end
  local entries = git.status(root)
  if #entries == 0 then
    return log.info "Commit: nothing to commit"
  end

  -- 1. qué entra: lo preparado o, si no hay nada, todo menos lo sensible
  local staged = vim.tbl_filter(function(e)
    return e.staged
  end, entries)
  local added, skipped = {}, {}
  if #staged == 0 then
    for _, e in ipairs(entries) do
      if e.letter == "U" then
        return log.warn("Commit: merge conflict in " .. e.path .. ": resolve it first")
      end
      table.insert(sensitive(e.path) and skipped or added, e.path)
    end
    if #added == 0 then
      return log.warn(
        "Commit: only sensitive files changed (" .. table.concat(skipped, ", ") .. "): stage them yourself"
      )
    end
    local ok, err = git.stage(root, added)
    if not ok then
      return log.error("Commit: git add failed: " .. text.clip(err, 300))
    end
    staged = vim.tbl_filter(function(e)
      return e.staged
    end, git.status(root))
  end

  local ai = require "commit.ai"
  local function undo()
    if #added > 0 then
      git.unstage(root, added)
    end
  end
  local model = ai.model()
  if not model then
    undo()
    return log.error "Commit: no agent backend available (<leader>am → Setup); <leader>Gc commits by hand"
  end

  local paths = vim.tbl_map(function(e)
    return e.path
  end, staged)
  local adds, dels = totals(staged)
  busy = true
  local t0 = vim.uv.hrtime()
  log.info(
    ("Commit: %d file%s +%d −%d → %s is writing the message…"):format(
      #paths,
      #paths == 1 and "" or "s",
      adds,
      dels,
      model
    )
  )

  ai.draft(paths, root, function(ok, result, usage)
    local function fail(msg)
      busy = false
      undo()
      log.error(
        "Commit: "
          .. msg
          .. " — nothing committed"
          .. (#added > 0 and " (files unstaged again)" or "")
          .. "; <leader>Gm to do it by hand"
      )
    end
    if not ok then
      return fail("AI failed: " .. text.clip(tostring(result), 200))
    end
    local header = result[1]
    local check = conventional.check(header)
    if check.state ~= "ok" then
      return fail(("the message `%s` is not valid (%s)"):format(header, check.err or check.state))
    end
    git.commit(root, header, false, function(committed, info)
      busy = false
      if not committed then
        undo()
        return log.error(
          ("Commit: git commit failed:\n%s\nNothing committed%s"):format(
            text.clip(info, 500),
            #added > 0 and " (files unstaged again)" or ""
          )
        )
      end
      vim.cmd "silent! checktime"
      pcall(function()
        require("gitsigns").refresh()
      end)
      local bits = { ("%s · %d file%s +%d −%d"):format(header, #paths, #paths == 1 and "" or "s", adds, dels) }
      bits[#bits + 1] = ("%s %.1fs"):format(model, (vim.uv.hrtime() - t0) / 1e9)
      if usage and usage.cost then
        bits[#bits + 1] = ("$%.4f"):format(usage.cost)
      end
      if #skipped > 0 then
        bits[#bits + 1] = ("left out: %s"):format(table.concat(skipped, ", "))
      end
      log.info(("✔ Committed %s %s · <leader>Ga amends"):format(info, table.concat(bits, " · ")))
    end)
  end)
end

return M
