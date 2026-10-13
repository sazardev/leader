-- ── Borrador del mensaje con el agente ───────────────────────────────────────
-- Un disparo, sin buffer ni presentador (agent/oneshot): mismo backend y modelo que las acciones, nivel ligero
-- (reasignable con agent.tiers.commit). Lo que se envía es exactamente lo que `describe` anuncia en el panel:
-- los archivos preparados (diff compacto, sin ruido, con tope repartido), la rama y los tipos. NO se envían los asuntos
-- de commits anteriores: el modelo copiaba su idioma (el vocabulario de scopes sale de ellos, en local).
-- El mensaje sale SIEMPRE en inglés y de una sola línea (menos salida = menos espera).
local conventional = require "commit.conventional"
local git = require "commit.git"

local M = {}

local function cfg()
  return require("core.settings").git.commit
end

---@param files string[] rutas preparadas
---@param root string
---@return string system, string prompt, { diff_chars: integer, truncated: boolean }
function M.build(files, root)
  local c = cfg()
  local types = vim.tbl_map(function(t)
    return t[1]
  end, c.types)
  local scopes = conventional.suggest_scopes(files, conventional.history_scopes(git.recent_subjects(root, c.history)))

  -- Todo en inglés y corto: el modelo devuelve SOLO la primera línea (menos salida = menos espera)
  local system = table.concat({
    "Write ONE git commit message for the staged diff. Conventional Commits, header line only.",
    "Output exactly one line: `type(scope): subject`. No body, no quotes, no code fences, no commentary.",
    "- ALWAYS English, even if the diff, comments or recent commits are in another language. Keep identifiers and paths as they are.",
    "- type: "
      .. table.concat(types, " | ")
      .. ". Pick by effect: feat = new capability, fix = bug, refactor = same behaviour, docs/test/chore/build/ci/style/perf as named.",
    #scopes > 0
        and ("- scope: lowercase noun of the area touched; prefer one of: %s. Omit it when the change is cross-cutting."):format(
          table.concat(scopes, ", ")
        )
      or "- scope: lowercase noun of the area touched; omit it when the change is cross-cutting.",
    ("- subject: imperative, lowercase first letter, no period, says WHAT changed (and why when it fits); the whole line at most %d characters."):format(
      c.subject_max
    ),
    "- Breaking change: `!` after the type/scope.",
    "- Many files: describe the one purpose that ties them together, not a list.",
  }, "\n")

  local diff, total, truncated = git.diff_for_ai(root, c.diff_max_chars)
  local branch = git.branch_name(root)
  local prompt = table.concat({
    "<branch>" .. branch .. "</branch>",
    "<files>\n" .. git.staged_numstat(root) .. "\n</files>",
    "<diff>\n" .. diff .. "\n</diff>",
  }, "\n")
  return system, prompt, { diff_chars = total, truncated = truncated }
end

--- Qué modelo lo escribiría (sin lanzar nada): "claude/haiku"
---@return string?
function M.model()
  local sel = require("agent.selection").current { name = "commit", tier = "light" }
  return sel and require("agent.selection").label(sel) or nil
end

--- Lo que se enviaría con N archivos preparados: para mostrarlo ANTES de gastar nada
---@param files string[]
---@param root string
---@return { model: string?, files: integer, diff_chars: integer, truncated: boolean, limit: integer }
function M.describe(files, root)
  local _, total, truncated = git.diff_for_ai(root, cfg().diff_max_chars)
  return { model = M.model(), files = #files, diff_chars = total, truncated = truncated, limit = cfg().diff_max_chars }
end

--- Pide el borrador. `cb(ok, lines | error, usage)`; devuelve el proceso para poder cancelarlo
---@param files string[]
---@param root string
---@param cb fun(ok: boolean, result: string[]|string, usage: table?)
---@return vim.SystemObj?
function M.draft(files, root, cb)
  local system, prompt = M.build(files, root)
  return require("agent").complete({ action = "commit", system = system, prompt = prompt }, function(ok, out, usage)
    if not ok then
      return cb(false, out)
    end
    -- solo la primera línea no vacía: si el modelo añade cuerpo o alternativas, se ignoran
    local header = vim.tbl_filter(function(l)
      return vim.trim(l) ~= ""
    end, conventional.clean_message(out))[1]
    if not header then
      return cb(false, "the model returned an empty message")
    end
    cb(true, { vim.trim(header) }, usage)
  end)
end

return M
