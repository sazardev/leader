-- `ddd` provider: the target's layer, how the project names things, the pieces around its entities
-- (port, implementation, wiring, use cases) and what the file already violates. All of it comes from the local
-- static analysis in agent/ddd; the first use walks the project (afterwards, cached by mtime).
local settings = require("core.settings").agent.ddd

local ROOT_MARKERS = {
  ".git",
  "go.mod",
  "package.json",
  "pyproject.toml",
  "Cargo.toml",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "*.csproj",
  "pubspec.yaml",
}

return {
  cap = settings.max_context_chars,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local abs = vim.api.nvim_buf_get_name(target.buf)
    local root = require("agent.ddd.index").root(target.buf)
    if abs == "" or abs:sub(1, #root) ~= root then
      return done(nil)
    end
    local rel = abs:sub(#root + 2)

    require("agent.ddd.index").get(root, function(index)
      local naming = require("agent.ddd.naming").profile(index)
      local rules = require "agent.ddd.rules"
      local aggregates = rules.aggregates(index)

      local text = table.concat(target.lines, "\n")
      local related = vim.tbl_filter(function(a)
        return a.file == rel or text:find("%f[%w_]" .. a.name .. "%f[^%w_]") ~= nil
      end, aggregates)
      local violations = vim.tbl_filter(function(v)
        return v.file == rel
      end, rules.violations(index))

      rules.wire(index, related, function()
        done(require("agent.ddd.profile").build(index, rel, naming, related, violations))
      end)
    end)
  end,
}
