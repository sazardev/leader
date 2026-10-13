-- ── Borrador del mensaje con el agente ───────────────────────────────────────
-- Un disparo, sin buffer ni presentador (agent/oneshot): mismo backend y modelo que las acciones, nivel ligero
-- (reasignable con agent.tiers.commit). Lo que se envía es exactamente lo que `describe` anuncia en el panel:
-- los archivos preparados (su diff, sin lockfiles, con tope), los últimos asuntos y la lista de tipos.
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

  local system = table.concat({
    "You write git commit messages in the Conventional Commits format.",
    "Output ONLY the commit message: no commentary, no code fences, no quotes.",
    "Format: `type(scope): subject`, then optionally a blank line and a body.",
    "- type: one of " .. table.concat(types, ", ") .. ".",
    #scopes > 0
        and ("- scope: a short lowercase noun for the area touched; prefer one of: %s. Omit it when the change is cross-cutting."):format(
          table.concat(scopes, ", ")
        )
      or "- scope: a short lowercase noun for the area touched; omit it when the change is cross-cutting.",
    ("- subject: imperative, lowercase first letter, no trailing period; the whole first line at most %d characters."):format(
      c.subject_max
    ),
    "- body: only when the change needs the WHY; wrap at 72 columns; plain sentences or `- ` bullets.",
    "- Breaking change: `!` after the type/scope and a `BREAKING CHANGE:` footer.",
    "- Exactly ONE commit message with a single header line: never list alternatives or a second header.",
    "- Match the style of the recent commits shown.",
    "- Write the message in " .. c.language .. ". Keep identifiers, paths and the type in their original form.",
  }, "\n")

  local diff, total, truncated = git.staged_diff(root, c.diff_max_chars)
  local prompt = table.concat({
    "<recent_commits>\n" .. git.recent_subjects(root, 15) .. "\n</recent_commits>",
    "<staged_files>\n" .. git.staged_stat(root) .. "\n</staged_files>",
    "<diff>\n" .. diff .. "\n</diff>",
    "<task>\nWrite the commit message for the staged changes.\n</task>",
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
  local _, total, truncated = git.staged_diff(root, cfg().diff_max_chars)
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
    local lines = conventional.clean_message(out)
    if vim.trim(table.concat(lines, "")) == "" then
      return cb(false, "the model returned an empty message")
    end
    cb(true, lines, usage)
  end)
end

return M
