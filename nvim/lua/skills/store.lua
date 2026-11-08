-- ── Skills: store on disk ──────────────────────────────────────────────────
-- Discovery igual que OpenCode: proyecto (`.agents/skills`, `.opencode/skills`,
-- `.claude/skills`) y global (`~/.config/opencode/skills`, `~/.claude/skills`,
-- `~/.agents/skills`). Cada skill es `<dir>/<id>/SKILL.md` o `<dir>/<id>.md`.
-- `skills-lock.json` (raíz del proyecto) guarda de dónde vino cada una;
-- el on/off vive en el propio frontmatter (`autoinvoke: false` = dormida).
-- Crear/editar/borrar nunca pisa: borrar va a la papelera de Leader (30 días).
local parse = require "skills.parse"
local project = require "utils.project"

local M = {}

---@param scope "project"|"global"?
---@return string[] dirs (las que existen)
function M.dirs(scope)
  local home = vim.fn.expand "~"
  local xdg = vim.env.XDG_CONFIG_HOME or (home .. "/.config")
  local out = {}
  if scope == "global" then
    out = { xdg .. "/opencode/skills", home .. "/.claude/skills", home .. "/.agents/skills" }
  else
    local root = project.git_root(project.file_dir())
    if root ~= "" then
      -- lo mismo en cada nivel hasta la raíz: OpenCode busca subiendo
      local dir = project.file_dir()
      while dir and dir ~= "" do
        for _, sub in ipairs { ".agents/skills", ".opencode/skills", ".claude/skills" } do
          out[#out + 1] = dir .. "/" .. sub
        end
        if dir == root then
          break
        end
        dir = vim.fs.dirname(dir)
        if dir == dir:match "^(.*)/[^/]*$" then
          break
        end
      end
      -- de-dup manteniendo orden
      local seen, dedup = {}, {}
      for _, d in ipairs(out) do
        if not seen[d] then
          seen[d] = true
          dedup[#dedup + 1] = d
        end
      end
      out = dedup
    else
      out = { ".agents/skills", ".opencode/skills", ".claude/skills" }
    end
  end
  return vim.tbl_filter(function(d)
    return vim.uv.fs_stat(d) ~= nil
  end, out)
end

---@param path string
---@return string, string? id, string? skill file
local function skill_from_path(path)
  if path:match "SKILL%.md$" then
    local dir = vim.fs.dirname(path)
    return vim.fs.basename(dir), path
  end
  return vim.fs.basename(path):gsub("%.md$", ""), path
end

---@param opts { scope?: "project"|"global", root?: string? }? root overrides the project dirs (tests)
---@return table[] skills: { id, name, description, body, autoinvoke, path, scope, dir }
function M.list(opts)
  opts = opts or {}
  local out, seen = {}, {}
  local dirs = opts.root and { opts.root } or M.dirs(opts.scope)
  local scope = opts.root and opts.root or opts.scope
  for _, base in ipairs(dirs) do
    local function add(path)
      local id, file = skill_from_path(path)
      if seen[id] then
        return -- el más cercano gana (proyecto sobre global en el orden de dirs)
      end
      seen[id] = true
      local text = project.read(file)
      if text then
        local parsed = parse.parse(text, id)
        out[#out + 1] = {
          id = parsed.id,
          name = parsed.name,
          description = parsed.description,
          body = parsed.body,
          autoinvoke = parsed.autoinvoke,
          valid = parsed.valid,
          errors = parsed.errors,
          path = file,
          scope = scope,
          dir = vim.fs.dirname(file),
          is_dir = file:match "SKILL%.md$" ~= nil,
        }
      end
    end
    for name, kind in vim.fs.dir(base, { depth = 3 }) do
      -- flat `id.md` only at the top; nested skills are `<group>/<id>/SKILL.md`
      local is_hidden = name:find("/%.", 1, true) ~= nil or name:find("^%.", 1, true) ~= nil
      local is_nested = name:find("/", 1, true) ~= nil
      if kind == "file" and not is_hidden and vim.fn.fnamemodify(name, ":t") == "SKILL.md" then
        add(base .. "/" .. name)
      elseif kind == "file" and not is_hidden and not is_nested and name:match "%.md$" then
        add(base .. "/" .. name)
      end
      -- (directory skills `<id>/SKILL.md` are caught above as nested SKILL.md)
    end
  end
  table.sort(out, function(a, b)
    return a.id:lower() < b.id:lower()
  end)
  return out
end

---@param id string
---@param opts { scope?: string, root?: string? }?
---@return table? skill
function M.get(id, opts)
  for _, s in ipairs(M.list(opts)) do
    if s.id == id then
      return s
    end
  end
end

---@param path string skill file
---@return boolean ok, string? err
local function write_file(path, text)
  local dir = vim.fs.dirname(path)
  vim.fn.mkdir(dir, "p")
  local f, err = io.open(path, "w")
  if not f then
    return false, tostring(err)
  end
  f:write(text)
  f:close()
  return true
end

--- Create one. Never overwrites. Returns path or nil + reason.
---@param id string
---@param description string
---@param body string
---@param opts { scope?: "project"|"global", root?: string? }?
---@return string? path, string? err
function M.create(id, description, body, opts)
  opts = opts or {}
  local errors = parse.validate { id = id, description = description, body = body }
  if #errors > 0 then
    return nil, table.concat(errors, "; ")
  end
  if id:find("[/\\]") or id:find("^%.") then
    return nil, "name cannot contain slashes or start with a dot"
  end
  local base
  if opts.root then
    base = opts.root
  elseif opts.scope == "global" then
    base = M.dirs("global")[1] or (vim.fn.expand "~" .. "/.config/opencode/skills")
  else
    base = project.git_root(project.file_dir()) .. "/.agents/skills"
  end
  local file = base .. "/" .. id .. "/SKILL.md"
  if vim.uv.fs_stat(file) or vim.uv.fs_stat(base .. "/" .. id .. ".md") then
    return nil, "already exists (edit it instead)"
  end
  local ok, err = write_file(file, parse.render(id, description, body, true))
  if not ok then
    return nil, err
  end
  local ok_lock, lock_err = pcall(function()
    M.lock_add(id, "created", file, opts.lock_path)
  end)
  if not ok_lock then
    return nil, "created, lock not saved: " .. tostring(lock_err)
  end
  return file
end

--- Save edits over the skill's file (frontmatter re-rendered, body kept).
---@param skill table skill from list/get
---@param opts { description?: string, body?: string, autoinvoke?: boolean }?
---@return boolean ok, string? err
function M.save(skill, opts)
  opts = opts or {}
  local description = opts.description or skill.description
  local body = opts.body or skill.body
  local autoinvoke = opts.autoinvoke
  if autoinvoke == nil then
    autoinvoke = skill.autoinvoke
  end
  local errors = parse.validate { id = skill.id, description = description, body = body }
  if #errors > 0 then
    return false, table.concat(errors, "; ")
  end
  return write_file(skill.path, parse.render(skill.id, description, body, autoinvoke))
end

--- Move it to Leader's trash (recoverable 30 days with <leader>Fu).
---@param skill table
---@return boolean ok, string? err
function M.remove(skill)
  local ops = require "files.ops"
  -- folders and files trash the same way
  local target = skill.is_dir and vim.fs.dirname(skill.path) or skill.path
  local entry, err = ops.trash(target)
  if not entry then
    return false, err
  end
  M.lock_remove(skill.id)
  return true
end

--- On/off without deleting: autoinvoke false hides it from the model.
---@param skill table
---@param enabled boolean
---@return boolean ok, string? err
function M.set_enabled(skill, enabled)
  return M.save(skill, { autoinvoke = enabled })
end

-- ── skills-lock.json ──────────────────────────────────────────────────────────

---@return string lock path (project root)
function M.lock_path()
  return project.git_root(project.file_dir()) .. "/skills-lock.json"
end

---@param path string?
---@return table { version: integer, skills: table<string, table> }
function M.lock_read(path)
  local f = io.open(path or M.lock_path(), "r")
  if not f then
    return { version = 1, skills = {} }
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  if ok and type(data) == "table" and type(data.skills) == "table" then
    return data
  end
  return { version = 1, skills = {} }
end

---@param path string
---@param lock table
local function lock_write(path, lock)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode(lock))
    f:close()
  end
end

---@param id string
---@param source string
---@param skill_path string
---@param lock_path string? override (tests point it at a temp file)
function M.lock_add(id, source, skill_path, lock_path)
  local path = lock_path or M.lock_path()
  local lock = M.lock_read(path)
  lock.skills[id] = { source = source, sourceType = "leader", skillPath = skill_path }
  lock_write(path, lock)
end

---@param id string
---@param lock_path string? override (tests point it at a temp file)
function M.lock_remove(id, lock_path)
  local path = lock_path or M.lock_path()
  local lock = M.lock_read(path)
  lock.skills[id] = nil
  lock_write(path, lock)
end

--- Project markers at the root (for infer.languages).
---@param root string?
---@return string[]
function M.markers(root)
  root = root or project.git_root(project.file_dir())
  local out = {}
  for name, kind in vim.fs.dir(root) do
    if kind == "file" then
      out[#out + 1] = name
    end
  end
  return out
end

--- Curated list for the marketplace / catalog (always available, offline).
M.CURATED = {
  { id = "caveman", name = "caveman", desc = "Ultra-compressed communication mode (-75% tokens)", repo = "juliusbrussee/caveman", tags = "tokens small", langs = {} },
  { id = "caveman-commit", name = "caveman-commit", desc = "Compressed conventional commits", repo = "juliusbrussee/caveman", tags = "tokens commits", langs = {} },
  { id = "code-reviewer", name = "code-reviewer", desc = "Reviews code for bugs, security and style", repo = "farmage/opencode-skills", tags = "review", langs = {} },
  { id = "test-master", name = "test-master", desc = "Writes real tests, fixes flaky ones", repo = "farmage/opencode-skills", tags = "tests", langs = {} },
  { id = "typescript-pro", name = "typescript-pro", desc = "Advanced TypeScript patterns and types", repo = "farmage/opencode-skills", tags = "typescript", langs = { "typescript" } },
  { id = "react-expert", name = "react-expert", desc = "React performance and component patterns", repo = "farmage/opencode-skills", tags = "react typescript", langs = { "typescript" } },
  { id = "nextjs-developer", name = "nextjs-developer", desc = "Next.js App Router and server components", repo = "farmage/opencode-skills", tags = "nextjs typescript", langs = { "typescript" } },
  { id = "python-pro", name = "python-pro", desc = "Python idioms, typing and packaging", repo = "farmage/opencode-skills", tags = "python", langs = { "python" } },
  { id = "go-pro", name = "go-pro", desc = "Go idioms, errors and project layout", repo = "farmage/opencode-skills", tags = "go", langs = { "go" } },
  { id = "postgres-pro", name = "postgres-pro", desc = "Postgres queries, indexes and migrations", repo = "farmage/opencode-skills", tags = "sql postgres", langs = {} },
  { id = "flutter-expert", name = "flutter-expert", desc = "Flutter widgets, state and build_runner", repo = "farmage/opencode-skills", tags = "flutter dart", langs = { "dart" } },
  { id = "api-designer", name = "api-designer", desc = "REST/GraphQL API design", repo = "farmage/opencode-skills", tags = "api", langs = {} },
  { id = "security-reviewer", name = "security-reviewer", desc = "Security audit for secrets and injection", repo = "farmage/opencode-skills", tags = "security", langs = {} },
  -- C#/.NET (la solución lee su stack: .sln/.csproj/global.json)
  { id = "dotnet-pro", name = "dotnet-pro", desc = "C#/.NET idioms, EF Core, DI and nullable", repo = "farmage/opencode-skills", tags = "csharp dotnet c#", langs = { "dotnet" } },
  { id = "php-pro", name = "php-pro", desc = "PHP and Composer idioms", repo = "farmage/opencode-skills", tags = "php", langs = { "php" } },
  { id = "ruby-pro", name = "ruby-pro", desc = "Ruby and Bundler idioms", repo = "farmage/opencode-skills", tags = "ruby", langs = { "ruby" } },
  { id = "elixir-pro", name = "elixir-pro", desc = "Elixir and Mix idioms", repo = "farmage/opencode-skills", tags = "elixir", langs = { "elixir" } },
  -- ambientes/deploy (importan tanto como el lenguaje)
  { id = "docker-pro", name = "docker-pro", desc = "Dockerfiles, multi-stage and compose", repo = "farmage/opencode-skills", tags = "docker deploy", langs = { "docker" } },
  { id = "kubernetes-specialist", name = "kubernetes-specialist", desc = "Helm charts, kustomize, probes and rollout", repo = "farmage/opencode-skills", tags = "kubernetes k8s deploy", langs = { "kubernetes" } },
  { id = "terraform-pro", name = "terraform-pro", desc = "Terraform plan/apply without surprises", repo = "farmage/opencode-skills", tags = "terraform infra deploy", langs = { "terraform" } },
  { id = "aws-pro", name = "aws-pro", desc = "AWS SAM, CDK, Lambda and serverless", repo = "farmage/opencode-skills", tags = "aws cloud deploy", langs = { "aws" } },
  { id = "gcp-pro", name = "gcp-pro", desc = "GCP, Firebase and App Engine", repo = "farmage/opencode-skills", tags = "gcp cloud deploy", langs = { "gcp" } },
  { id = "cloudflare-expert", name = "cloudflare-expert", desc = "Cloudflare Workers and Pages (wrangler)", repo = "farmage/opencode-skills", tags = "cloudflare workers deploy", langs = { "cloudflare" } },
  { id = "netlify-expert", name = "netlify-expert", desc = "Netlify deploys, redirects and edge functions", repo = "farmage/opencode-skills", tags = "netlify deploy edge", langs = { "netlify" } },
  { id = "vercel-expert", name = "vercel-expert", desc = "Vercel deploys and edge config", repo = "farmage/opencode-skills", tags = "vercel deploy edge", langs = { "vercel" } },
  { id = "azure-pro", name = "azure-pro", desc = "Azure, Bicep and Azure Developer CLI", repo = "farmage/opencode-skills", tags = "azure cloud deploy", langs = { "azure" } },
  { id = "devops-engineer", name = "devops-engineer", desc = "CI/CD, deploys and observability", repo = "farmage/opencode-skills", tags = "devops ci deploy docker k8s terraform", langs = { "docker", "terraform", "kubernetes", "ci" } },
}

return M
