-- ── Skills: tolerance / adoption (repo already worked) ─────────────────────
-- A repo oldie, legacy or ya trabajado already has skills, agents, design,
-- STACK/DESIGN/SPEC... Leader detects that in automatic, SHOWS it and ADJUSTS:
-- never overwrites, never duplicates, suggests only what's missing.
-- `analyze` is pure (files/markers/skills/docs in); `collect` does the IO.
-- Tested in scripts/test-skills.lua.
local M = {}

--- Agent files that mean "this repo already talks to agents".
M.AGENTS = { "AGENTS.md", "CLAUDE.md", ".agent.md", ".agents", ".claude", ".opencode" }

--- Kit docs that mean "already documented" (same list as kit/compose DOCS).
M.DOCS = { "AGENTS.md", "STACK.md", "DESIGN.md", "SPEC.md", "PROGRESS.md" }

--- Modern markers that mean "stack conocido" (reuse infer order via caller).
M.MODERN = {
  "go.mod",
  "package.json",
  "pubspec.yaml",
  "pyproject.toml",
  "Cargo.toml",
  "Package.swift",
  "pom.xml",
  "composer.json",
  "Gemfile",
  "mix.exs",
  "Dockerfile",
  "vercel.json",
  "netlify.toml",
  "wrangler.toml",
}

---@class AdoptProfile
---@field skills_total integer
---@field invalid string[]
---@field dormant string[]
---@field agents string[]
---@field docs string[]
---@field has_lock boolean
---@field legacy boolean
---@field hints string[]

--- Pure: what this repo already is, and what Leader must therefore NOT do.
---@param opts { files?: string[], markers?: string[], skills?: table[], docs?: table<string, boolean>, agents?: string[], has_lock?: boolean }
---@return AdoptProfile
function M.analyze(opts)
  opts = opts or {}
  local skills = opts.skills or {}
  local invalid, dormant = {}, {}
  for _, s in ipairs(skills) do
    if not s.valid then
      invalid[#invalid + 1] = s.id
    elseif not s.autoinvoke then
      dormant[#dormant + 1] = s.id
    end
  end
  local agents = opts.agents or {}
  local docs = {}
  if opts.docs then
    for _, d in ipairs(M.DOCS) do
      if opts.docs[d] then
        docs[#docs + 1] = d
      end
    end
  end
  local markers = opts.markers or {}
  local marker_set = {}
  for _, m in ipairs(markers) do
    marker_set[m] = true
  end
  local modern = false
  for _, m in ipairs(M.MODERN) do
    if marker_set[m] then
      modern = true
      break
    end
  end
  -- legacy: hay repo (archivos) pero ningún marker moderno y hay algo que lo delate
  local legacy = (not modern) and (#(opts.files or {}) > 5 or marker_set["Makefile"] == true)
  local hints = {}
  if #skills > 0 then
    hints[#hints + 1] = ("ya hay %d skill%s: se conservan, no se duplican"):format(#skills, #skills == 1 and "" or "s")
  end
  if #invalid > 0 then
    hints[#hints + 1] = ("%d inválida%s sin description (%s): no se anuncia al modelo, edítala con e"):format(
      #invalid,
      #invalid == 1 and "" or "s",
      table.concat(invalid, ", ")
    )
  end
  if #dormant > 0 then
    hints[#hints + 1] = ("dormida%s: %s (Space la despierta)"):format(#dormant == 1 and "" or "s", table.concat(dormant, ", "))
  end
  if opts.has_lock then
    hints[#hints + 1] = "skills-lock.json presente: se respeta"
  end
  for _, a in ipairs(agents) do
    if a == "CLAUDE.md" and not vim.tbl_contains(docs, "AGENTS.md") then
      hints[#hints + 1] = "CLAUDE.md sin AGENTS.md: <leader>aSc lo enlaza, no se crea de cero"
    elseif a == "AGENTS.md" then
      hints[#hints + 1] = "AGENTS.md ya existe: no se sobrescribe (kit confirma + papelera)"
    end
    if a == ".claude/skills" or a == "~/.claude/skills" then
      hints[#hints + 1] = ".claude/skills presente: se lee igual que .agents/skills"
    end
  end
  for _, d in ipairs(docs) do
    if d == "STACK.md" then
      hints[#hints + 1] = "STACK.md ya documentado: <leader>aS ajusta, no se crea de cero"
    elseif d == "DESIGN.md" then
      hints[#hints + 1] = "DESIGN.md ya existe: el sistema de diseño se respeta"
    elseif d == "SPEC.md" then
      hints[#hints + 1] = "SPEC.md ya existe: los módulos se añaden, no se reescribe"
    end
  end
  if legacy then
    hints[#hints + 1] = "repo legacy/oldie sin manifests modernos: solo token-savers, sin skills de stack forzadas"
  end
  return {
    skills_total = #skills,
    invalid = invalid,
    dormant = dormant,
    agents = agents,
    docs = docs,
    has_lock = opts.has_lock == true,
    legacy = legacy,
    hints = hints,
  }
end

--- IO: survey this project without touching anything.
---@param root string?
---@return AdoptProfile
function M.collect(root)
  local project = require "utils.project"
  root = root or project.git_root(project.file_dir())
  local function has(name)
    return vim.uv.fs_stat(root .. "/" .. name) ~= nil
  end
  local agents = {}
  for _, a in ipairs(M.AGENTS) do
    if has(a) then
      agents[#agents + 1] = a
    end
  end
  local docs = {}
  for _, d in ipairs(M.DOCS) do
    if has(d) then
      docs[d] = true
    end
  end
  local store = require "skills.store"
  local files, markers = {}, {}
  -- files: git si hay, si no un walk somero (solo los top-level alcanzan para legacy)
  local ok, res = pcall(function()
    return vim.system({ "git", "ls-files", "--cached", "--others", "--exclude-standard" }, { cwd = root, text = true }):wait()
  end)
  if ok and res and res.code == 0 and res.stdout ~= "" then
    files = vim.tbl_filter(function(f)
      return f ~= ""
    end, vim.split(res.stdout, "\n", { plain = true }))
  else
    for name, kind in vim.fs.dir(root, { depth = 1 }) do
      if kind == "file" then
        files[#files + 1] = name
      end
    end
  end
  for _, f in ipairs(files) do
    if not f:find("/", 1, true) then
      markers[#markers + 1] = f
    end
  end
  return M.analyze {
    files = files,
    markers = markers,
    skills = store.list(),
    docs = docs,
    agents = agents,
    has_lock = has "skills-lock.json",
  }
end

--- Adjust suggestions with what already exists: in a legacy repo without
--- modern markers, stack skills are NOT forced (only token-savers + keep).
---@param suggestions table[]
---@param profile AdoptProfile
---@return table[]
function M.adjust(suggestions, profile)
  if not profile.legacy then
    return suggestions
  end
  -- in legacy: the token-savers (caveman) and what is already here stay; new stack installs go
  local keep = { caveman = true, ["caveman-commit"] = true }
  return vim.tbl_filter(function(s)
    return s.action == "keep" or keep[s.id] == true
  end, suggestions)
end

return M
