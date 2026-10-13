-- ── JVM actions (Java / Kotlin): Gradle or Maven ─────────────────────────────
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local MARKERS = { "gradlew", "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pom.xml" }

---@param root string
---@return string
local function maven_run(root)
  local pom = project.read(root .. "/pom.xml") or ""
  return pom:find("spring-boot", 1, true) and "spring-boot:run" or "compile exec:java"
end

--- Action that runs the Gradle or Maven goal depending on the project
---@param goal { gradle: string, maven: string|fun(root: string): string }
local function build_tool(goal)
  return function()
    local root = vim.fs.root(0, MARKERS)
    if not root then
      return log.warn "No Gradle/Maven project (build.gradle / pom.xml)"
    end
    local cmd
    if project.has(root, "pom.xml") then
      local maven = type(goal.maven) == "function" and goal.maven(root) or goal.maven
      cmd = ("%s %s"):format(project.has(root, "mvnw") and "./mvnw" or "mvn", maven)
    else
      cmd = ("%s %s"):format(project.has(root, "gradlew") and "./gradlew" or "gradle", goal.gradle)
    end
    terminal.run(cmd, root)
  end
end

return {
  { "r", "run", build_tool { gradle = "run", maven = maven_run } },
  { "b", "build", build_tool { gradle = "build", maven = "package" } },
  { "m", "test", build_tool { gradle = "test", maven = "test" } },
  { "v", "check / verify", build_tool { gradle = "check", maven = "verify" } },
  { "c", "clean", build_tool { gradle = "clean", maven = "clean" } },
}
