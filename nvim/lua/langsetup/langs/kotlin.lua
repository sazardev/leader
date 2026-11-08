-- Kotlin setup (<leader>kS): ktlint, .editorconfig, .tool-versions, Docker, CI. Filled from
-- build.gradle.kts / pom.xml or the folder's name.
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "Kotlin" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == "build.gradle.kts" or name == "build.gradle" or name == "pom.xml" or name == "settings.gradle" or name == "settings.gradle.kts"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local gradle = read(root .. "/build.gradle.kts") or read(root .. "/build.gradle") or ""
  local pom = read(root .. "/pom.xml") or ""
  local name = gradle:match 'rootProject.name%s*=%s*"([^"]+)"' or pom:match "<artifactId>([^<]+)</artifactId>"
    or vim.fs.basename(root)
  local kotlin = gradle:match "kotlin%s*[\"']([%d%.]+)[\"']" or "2.0.0"
  local jvm = gradle:match "jvmTarget%s*=.*\"([%d%.]+)\"" or "17"
  return { name = name, kotlin = kotlin, jvm = jvm }
end

M.topics = {
  { id = "ktlint", key = "l", label = "ktlint config", default = "standard" },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "jvm", core = true },
  { id = "toolversions", key = "v", label = ".tool-versions (Java + Kotlin)", default = "pinned", core = true },
  { id = "docker", key = "d", label = "Dockerfile (temurin)", default = "temurin" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "jvm" },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "gradle", alts = { ".github/workflows/ci.yaml" } },
}

return M
