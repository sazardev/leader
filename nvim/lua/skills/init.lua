-- ── Skills: public facade ──────────────────────────────────────────────────
-- `<leader>aK` opens the marketplace (skills/market.lua). This facade is the
-- only thing menus/prefs/providers use; the rest is not imported from outside.
-- A class of its own (like agent/kit): one folder, one contract per piece:
--   parse.lua    pure frontmatter         store.lua    discovery + file ops
--   infer.lua    pure who-gets-what       catalog.lua  marketplaces + install
--   adopt.lua    pure tolerance (legacy/already-worked repos) + collect
--   market.lua   the full-screen marketplace UI
-- The agent reads them two ways: backends with a `skill` tool (opencode) get
-- them for free once installed; tool-less ones (claude -p, ollama) receive ONE
-- relevant body as a context section (`skills` provider, cap 1200 chars).
local M = {}

---@param opts { scope?: string }?
---@return table[]
function M.list(opts)
  return require("skills.store").list(opts)
end

---@param id string
---@param opts { scope?: string }?
---@return table? skill
function M.get(id, opts)
  return require("skills.store").get(id, opts)
end

--- Class of the current model (small/medium/strong): the same the pipeline uses.
---@return string
function M.class()
  local ok, selection = pcall(require, "agent.selection")
  if not ok then
    return "medium"
  end
  local sel = selection.current()
  if not sel then
    return "medium"
  end
  local okp, profiles = pcall(require, "agent.profiles")
  if not okp then
    return "medium"
  end
  local cap = require("core.settings").agent.capability
  local profile = cap.enabled and profiles.resolve(sel, nil, cap, profiles.load()) or nil
  return profile and profile.name or profiles.by_name(sel.backend, sel.model)
end

--- Tolerance profile of THIS repo (legacy / already-worked): what exists, what is invalid.
---@return table AdoptProfile
function M.facts()
  return require("skills.adopt").collect()
end

--- Suggestions for THIS backend/model/project (0 tokens, no question).
--- Tolerante: en un repo legacy se ajustan (solo token-savers + keep).
---@return table[] SkillSuggestion[]
function M.suggest()
  local store, infer = require "skills.store", require "skills.infer"
  local installed, enabled, disabled = {}, {}, {}
  for _, s in ipairs(store.list()) do
    installed[s.id] = true
    if s.autoinvoke then
      enabled[s.id] = true
    else
      disabled[s.id] = true
    end
  end
  local cfg = require("core.settings").skills
  if cfg.disabled then
    for _, id in ipairs(cfg.disabled) do
      disabled[id] = true
    end
  end
  local suggestions = infer.suggest {
    class = M.class(),
    markers = store.markers(),
    installed = installed,
    enabled = enabled,
    disabled = disabled,
    auto = cfg.auto ~= false and cfg.enabled ~= false,
  }
  local ok, adopt = pcall(require, "skills.adopt")
  if ok then
    return adopt.adjust(suggestions, adopt.collect())
  end
  return suggestions
end

--- Doctor: what was detected and how Leader adapts (tolerance, read-only).
function M.doctor()
  local facts = M.facts()
  local lines = {
    { { ("Detected: %d skill(s) · %d agent file(s) · %d doc(s)"):format(facts.skills_total, #facts.agents, #facts.docs), "NvModalMuted" } },
    "",
  }
  if #facts.hints == 0 then
    lines[#lines + 1] = { { "Nothing to adjust: clean repo, Leader infers from scratch.", "NvModalMuted" } }
  else
    for _, h in ipairs(facts.hints) do
      lines[#lines + 1] = { { "  · " .. h, "NvModalMuted" } }
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = { { "  Leader never overwrites: create refuses, delete goes to trash.", "NvModalMuted" } }
  require("utils.modal").confirm(lines, { title = "Skills · detected", confirm = "Close", cancel = "Close" }, function() end)
end

--- Install every "install"/"enable" suggestion (the 0-config step). Returns counts.
---@param cb fun(installed: integer, enabled: integer, failed: integer)?
function M.apply_suggestions(cb)
  local suggestions = M.suggest()
  local store, catalog = require "skills.store", require "skills.catalog"
  local to_install, to_enable = 0, 0
  for _, s in ipairs(suggestions) do
    if s.action == "install" then
      to_install = to_install + 1
      local entry
      for _, e in ipairs(store.CURATED) do
        if e.id == s.id then
          entry = e
          break
        end
      end
      if entry then
        catalog.install(entry, nil, function(ok, detail)
          if ok then
            require("utils.log").info("Skills: " .. detail)
          else
            require("utils.log").warn("Skills: " .. (detail or s.id))
          end
        end)
      end
    elseif s.action == "enable" then
      to_enable = to_enable + 1
      local skill = store.get(s.id)
      if skill then
        store.set_enabled(skill, true)
      end
    end
  end
  require("utils.log").info(("Skills: %d to install, %d to enable (by model %s)"):format(to_install, to_enable, M.class()))
  if cb then
    cb(to_install, to_enable, 0)
  end
end

--- Error message shown when skills are disabled in settings.
local function disabled_msg()
  return "Skills: disabled (settings.skills.enabled = false)"
end

--- Best skill body for a prompt: language + file name + task words (0 tokens).
---@param hint string task/file text (lowercased outside)
---@param limit integer? max skills to return (default 1)
---@return table[] skills (with body)
function M.match_for_prompt(hint, limit)
  if require("core.settings").skills.enabled == false then
    return {}
  end
  limit = limit or 1
  local infer = require "skills.infer"
  local scored = {}
  for _, s in ipairs(M.list()) do
    if s.autoinvoke and s.valid and s.body ~= "" then
      local score = infer.score({ id = s.id, description = s.description .. "\n" .. vim.fn.fnamemodify(s.path, ":t") }, (hint or ""):lower())
      if score > 0 then
        scored[#scored + 1] = { skill = s, score = score }
      end
    end
  end
  table.sort(scored, function(a, b)
    return a.score > b.score
  end)
  local out = {}
  for i = 1, math.min(limit, #scored) do
    out[#out + 1] = scored[i].skill
  end
  return out
end

--- One-line list `id: description` for backends that inline an <available_skills> block.
---@return string
function M.available_list()
  if require("core.settings").skills.enabled == false then
    return ""
  end
  local lines = {}
  for _, s in ipairs(M.list()) do
    if s.autoinvoke and s.description ~= "" then
      lines[#lines + 1] = ("- %s: %s"):format(s.id, s.description:gsub("%s+", " "))
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or ""
end

--- Opens the marketplace (same full-screen widget as aSm: Esc/h goes back).
function M.open()
  if require("core.settings").skills.enabled == false then
    return require("utils.log").warn(disabled_msg())
  end
  require("skills.market").open()
end

--- New skill: name → description → body (template). Stays in the marketplace.
function M.create()
  local modal = require "utils.modal"
  modal.input({ { { "New skill: id (a-z, -, _) ", modal.hl.key } } }, { title = "Skill", confirm = "Next" }, function(id)
    id = vim.trim((id or ""):gsub("[^%w%-%_]", "-"):lower())
    if id == "" then
      return
    end
    modal.input({ { { "What it is for (one trigger line the model reads) ", modal.hl.key } } }, { title = "Skill", confirm = "Next" }, function(desc)
      modal.input({ { { "## Instructions (what the agent must do)", modal.hl.key } } }, { title = "Skill", confirm = "Create" }, function(body)
        local path, err = require("skills.store").create(id, desc, body, {})
        if path then
          require("utils.log").info("Skills: " .. id .. " created (edit with <leader>aKe)")
        else
          require("utils.log").warn("Skills: " .. (err or "failed"))
        end
      end)
    end)
  end)
end

--- Edit the skill under the cursor's skills list (or by id when given).
---@param id string?
function M.edit(id)
  local skill = id and M.get(id) or (function()
    local items = vim.tbl_map(function(s)
      return { label = s.id .. " — " .. s.description, value = s.id }
    end, M.list())
    return nil
  end)()
  if not skill then
    if id then
      return require("utils.log").warn("Skills: " .. id .. " not found")
    end
    -- no id: open the marketplace and let `e` do it there (keeps one entry point)
    return M.open()
  end
  vim.cmd.edit(vim.fn.fnameescape(skill.path))
end

return M
