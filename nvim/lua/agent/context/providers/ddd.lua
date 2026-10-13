-- Proveedor `ddd`: la capa del objetivo, cómo se nombra el proyecto, las piezas que rodean a sus entidades
-- (puerto, implementación, cableado, casos de uso) y lo que ya viola el archivo. Todo sale del análisis estático
-- local de agent/ddd; el primer uso recorre el proyecto (después, caché por mtime).
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
