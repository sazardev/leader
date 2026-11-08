-- ── Skills: inference (pure) ────────────────────────────────────────────────
-- 0 configuración: qué skills activar sin preguntar, a partir de lo que ya
-- sabes: backend+modelo (clase pequeña/mediana/fuerte), lenguajes del
-- proyecto (por manifests) y qué ya está instalado/habilitado.
-- Sin I/O: `detect` vive en skills/store (markers) y aquí solo se sugiere.
-- Tested in scripts/test-skills.lua.
local M = {}

--- Manifest → stack/lenguaje/ambiente. `go.mod` gana sobre un `package.json`
--- suelto, etc. `glob = "*.sln"` es sufijo (C#/.tf no tienen nombre fijo).
M.MARKERS = {
  { marker = "go.mod", lang = "go" },
  { marker = "pubspec.yaml", lang = "dart" },
  { marker = "package.json", lang = "typescript" },
  { marker = "tsconfig.json", lang = "typescript" },
  { marker = "pyproject.toml", lang = "python" },
  { marker = "requirements.txt", lang = "python" },
  { marker = "Cargo.toml", lang = "rust" },
  { marker = "Package.swift", lang = "swift" },
  { marker = "pom.xml", lang = "jvm" },
  { marker = "build.gradle", lang = "jvm" },
  { marker = "build.gradle.kts", lang = "jvm" },
  { marker = "composer.json", lang = "php" },
  { marker = "Gemfile", lang = "ruby" },
  { marker = "mix.exs", lang = "elixir" },
  -- C#/.NET: los proyectos se llaman como la solución/clase, no un fijo
  { marker = "*.sln", lang = "dotnet" },
  { marker = "*.csproj", lang = "dotnet" },
  { marker = "global.json", lang = "dotnet" },
  { marker = "Directory.Build.props", lang = "dotnet" },
  { marker = "nuget.config", lang = "dotnet" },
  -- Ambientes/deploy: el stack manda tanto como el lenguaje
  { marker = "Dockerfile", lang = "docker" },
  { marker = "docker-compose.yml", lang = "docker" },
  { marker = "docker-compose.yaml", lang = "docker" },
  { marker = "compose.yaml", lang = "docker" },
  { marker = "Containerfile", lang = "docker" },
  { marker = "*.tf", lang = "terraform" },
  { marker = "*.tfvars", lang = "terraform" },
  { marker = "Chart.yaml", lang = "kubernetes" },
  { marker = "kustomization.yaml", lang = "kubernetes" },
  { marker = "serverless.yml", lang = "aws" },
  { marker = "serverless.yaml", lang = "aws" },
  { marker = "template.yaml", lang = "aws" },
  { marker = "cdk.json", lang = "aws" },
  { marker = "amplify.yml", lang = "aws" },
  { marker = "firebase.json", lang = "gcp" },
  { marker = "app.yaml", lang = "gcp" },
  { marker = "wrangler.toml", lang = "cloudflare" },
  { marker = "wrangler.json", lang = "cloudflare" },
  { marker = "wrangler.jsonc", lang = "cloudflare" },
  { marker = "netlify.toml", lang = "netlify" },
  { marker = "vercel.json", lang = "vercel" },
  { marker = "azure.yaml", lang = "azure" },
  { marker = "*.bicep", lang = "azure" },
  { marker = ".gitlab-ci.yml", lang = "ci" },
  { marker = "Jenkinsfile", lang = "ci" },
}

---@param name string file name at the project root
---@param entry { marker: string }
---@return boolean
local function marker_matches(name, entry)
  local marker = entry.marker
  if marker:sub(1, 2) == "*." then
    local suffix = marker:sub(2) -- ".sln"
    return name:sub(-#suffix) == suffix
  end
  return name == marker
end

---@param markers string[] file names at the project root
---@return string[] languages/stacks, de-duped in marker order
function M.languages(markers)
  local have, out = {}, {}
  local present = markers or {}
  for _, entry in ipairs(M.MARKERS) do
    if not have[entry.lang] then
      for _, name in ipairs(present) do
        if marker_matches(name, entry) then
          have[entry.lang] = true
          out[#out + 1] = entry.lang
          break
        end
      end
    end
  end
  return out
end

--- Lenguaje/stack/ambiente → skills que valen la pena (ids del catálogo, no archivos).
M.STACK = {
  go = { { id = "go-pro", why = "Go: idioms del proyecto" }, { id = "test-master", why = "Go: tests que sí pasan" } },
  dart = { { id = "flutter-expert", why = "Dart/Flutter del pubspec" } },
  typescript = {
    { id = "typescript-pro", why = "TypeScript del package.json" },
    { id = "react-expert", why = "React en el stack" },
  },
  python = { { id = "python-pro", why = "Python del pyproject" } },
  rust = { { id = "rust-pro", why = "Rust del Cargo.toml" } },
  swift = { { id = "swift-expert", why = "SwiftPM del Package.swift" } },
  jvm = { { id = "java-architect", why = "JVM por pom/build.gradle" } },
  dotnet = {
    { id = "dotnet-pro", why = "C#/.NET: la solución lee su stack (.sln/.csproj)" },
    { id = "test-master", why = ".NET: tests con dotnet test que sí pasan" },
  },
  php = { { id = "php-pro", why = "PHP del composer.json" } },
  ruby = { { id = "ruby-pro", why = "Ruby del Gemfile" } },
  elixir = { { id = "elixir-pro", why = "Elixir del mix.exs" } },
  -- ambientes/deploy: valen tanto como el lenguaje
  docker = {
    { id = "docker-pro", why = "Docker: imagen/compose del Dockerfile" },
    { id = "devops-engineer", why = "deploy: dónde va la imagen" },
  },
  terraform = {
    { id = "terraform-pro", why = "Terraform: infra como código (.tf)" },
    { id = "devops-engineer", why = "deploy: plan/apply sin sorpresas" },
  },
  kubernetes = {
    { id = "kubernetes-specialist", why = "Kubernetes: Helm/kustomize del Chart" },
    { id = "devops-engineer", why = "deploy: rollout y probes" },
  },
  aws = { { id = "aws-pro", why = "AWS: SAM/CDK/serverless del template" } },
  gcp = { { id = "gcp-pro", why = "GCP: Firebase/App Engine del firebase.json" } },
  cloudflare = { { id = "cloudflare-expert", why = "Cloudflare: Workers (wrangler)" } },
  netlify = { { id = "netlify-expert", why = "Netlify: deploys y edge del netlify.toml" } },
  vercel = { { id = "vercel-expert", why = "Vercel: deploys del vercel.json" } },
  azure = { { id = "azure-pro", why = "Azure: Bicep/azd del azure.yaml" } },
  ci = { { id = "devops-engineer", why = "CI: pipeline del .gitlab-ci/Jenkinsfile" } },
}

--- Skills que de verdad ahorran tokens en modelos pequeños (se activan solos).
M.TOKEN = {
  { id = "caveman", why = "ahorra tokens: modo ultra-corto (-75%)" },
  { id = "caveman-commit", why = "ahorra tokens: commits cortos reales" },
}

---@class SkillSuggestion
---@field id string
---@field why string
---@field action "install"|"enable"|"keep"|"skip" install = falta y vale, enable = instalada pero dormida, keep = ya activa, skip = desactivada por el usuario
---@field installed boolean

--- What to do for the given situation. Never asks: if it is worth it, it is "install".
---@param opts { class: string?, markers: string[]?, installed: table<string, boolean>?, enabled: table<string, boolean>?, disabled: table<string, boolean>?, auto: boolean? }
---@return SkillSuggestion[]
function M.suggest(opts)
  opts = opts or {}
  if opts.auto == false then
    return {}
  end
  local installed = opts.installed or {}
  local enabled = opts.enabled or {}
  local disabled = opts.disabled or {}
  local want, order = {}, {}
  local function want_id(id, why)
    if disabled[id] then
      return
    end
    if not want[id] then
      want[id] = why
      order[#order + 1] = id
    end
  end
  -- modelo pequeño: el ahorro manda, antes que el stack
  if opts.class == "small" then
    for _, t in ipairs(M.TOKEN) do
      want_id(t.id, t.why)
    end
  elseif opts.class == "medium" then
    want_id(M.TOKEN[1].id, M.TOKEN[1].why)
  end
  -- stack: cada lenguaje añade lo suyo (un modelo fuerte solo recibe stack)
  for _, lang in ipairs(M.languages(opts.markers or {})) do
    for _, s in ipairs(M.STACK[lang] or {}) do
      want_id(s.id, s.why)
    end
  end
  local out = {}
  for _, id in ipairs(order) do
    if disabled[id] then
      out[#out + 1] = { id = id, why = want[id], action = "skip", installed = installed[id] == true }
    elseif installed[id] and enabled[id] then
      out[#out + 1] = { id = id, why = want[id], action = "keep", installed = true }
    elseif installed[id] then
      out[#out + 1] = { id = id, why = want[id], action = "enable", installed = true }
    else
      out[#out + 1] = { id = id, why = want[id], action = "install", installed = false }
    end
  end
  return out
end

--- Keyword score of a skill description against a hint (language + file + task).
--- Pure: `match_for_prompt` vive en skills/init y aquí solo el puntaje.
---@param skill { id: string, description: string }
---@param hint string lowercased, padded with spaces
---@return integer score
function M.score(skill, hint)
  if not hint or hint == "" then
    return 0
  end
  local text = (" " .. (skill.id .. " " .. (skill.description or "")):lower():gsub("[^%w%+%.%-%_]", " ") .. " ")
  local score = 0
  for word in hint:gmatch "[%w%+%.%-%_]+" do
    if #word >= 3 and text:find(" " .. word .. " ", 1, true) then
      score = score + 1
    end
  end
  -- id exacto vale doble (caveman en un commit → caveman-commit)
  if hint:find(skill.id:lower(), 1, true) then
    score = score + 2
  end
  return score
end

return M
