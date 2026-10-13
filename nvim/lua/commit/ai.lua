-- ── Message draft with the agent ─────────────────────────────────────────────
-- One shot, no buffer or presenter (agent/oneshot): same backend and model as the actions, light tier
-- (reassignable with agent.tiers.commit). What is sent is exactly what `describe` announces in the panel:
-- the staged files (compact diff, noise-free, with a split cap), the branch and the types. The subjects
-- of previous commits are NOT sent: the model copied their language (the scope vocabulary comes from them, locally).
-- The message ALWAYS comes out in English and on a single line (less output = less waiting).
local conventional = require "commit.conventional"
local git = require "commit.git"

local M = {}

local function cfg()
  return require("core.settings").git.commit
end

---@param files string[] staged paths
---@param root string
---@return string system, string prompt, { diff_chars: integer, truncated: boolean }
function M.build(files, root)
  local c = cfg()
  local types = vim.tbl_map(function(t)
    return t[1]
  end, c.types)
  local scopes = conventional.suggest_scopes(files, conventional.history_scopes(git.recent_subjects(root, c.history)))

  -- All in English and short: the model returns ONLY the first line (less output = less waiting)
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

--- Which model would write it (without launching anything): "claude/haiku"
---@return string?
function M.model()
  local sel = require("agent.selection").current { name = "commit", tier = "light" }
  return sel and require("agent.selection").label(sel) or nil
end

--- What would be sent with N staged files: to show it BEFORE spending anything
---@param files string[]
---@param root string
---@return { model: string?, files: integer, diff_chars: integer, truncated: boolean, limit: integer }
function M.describe(files, root)
  local _, total, truncated = git.diff_for_ai(root, cfg().diff_max_chars)
  return { model = M.model(), files = #files, diff_chars = total, truncated = truncated, limit = cfg().diff_max_chars }
end

--- Requests the draft. `cb(ok, lines | error, usage)`; returns the process so it can be cancelled
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
    -- only the first non-empty line: if the model adds a body or alternatives, they are ignored
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
