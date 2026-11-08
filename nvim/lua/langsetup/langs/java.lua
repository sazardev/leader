-- Java setup (<leader>jS): spotless/checkstyle, .editorconfig, .tool-versions, Docker, CI. Filled from
-- pom.xml or build.gradle (artifactId / rootProject.name) or the folder's name.
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "Java" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == "pom.xml" or name == "build.gradle" or name == "build.gradle.kts" or name == "settings.gradle" or name == "settings.gradle.kts"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local pom = read(root .. "/pom.xml") or ""
  local gradle = read(root .. "/build.gradle.kts") or read(root .. "/build.gradle") or ""
  local name = pom:match "<artifactId>([^<]+)</artifactId>" or gradle:match 'rootProject.name%s*=%s*"([^"]+)"'
    or pom:match "<name>([^<]+)</name>" or vim.fs.basename(root)
  local java = pom:match "<maven.compiler.release>([^<]+)</maven.compiler.release>"
    or gradle:match 'sourceCompatibility%s*=.*JAVA_([%d_]+)' or "21"
  java = java:gsub("_", ".")
  local has_maven = tostring(vim.uv.fs_stat(root .. "/pom.xml") ~= nil)
  return { name = name, java = java, maven = has_maven }
end

M.topics = {
  { id = "formatter", key = "f", label = "Spotless / Checkstyle config", default = "gradle" },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "jvm", core = true },
  { id = "toolversions", key = "v", label = ".tool-versions (Java)", default = "pinned", core = true },
  { id = "docker", key = "d", label = "Dockerfile (temurin)", default = "temurin" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "jvm" },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "maven", alts = { ".github/workflows/ci.yaml" } },
}

function M.hint(topic)
  if topic.id == "formatter" then
    return "spotless: `./mvnw spotless:apply` or `./gradlew spotlessApply`"
  elseif topic.id == "ci" then
    return "the maven variant runs `mvn -q -U verify`; change to gradle if your project uses Gradle"
  end
end

return M
