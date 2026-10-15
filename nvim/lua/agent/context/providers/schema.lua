-- `schema` provider: for a persistence adapter (repository), the REAL table of its entity (SQL migrations or
-- schema.prisma, with later changes) and the database in use (dialect, driver, parameter style).
-- Silent if the code is not persistence: a service or a handler pays nothing for this.
local contracts = require "agent.repository.contracts"
local imports = require "agent.ddd.imports"
local index = require "agent.ddd.index"
local layers = require "agent.ddd.layers"
local names = require "agent.repository.contracts.names"
local schema = require "agent.repository.contracts.schema"

local PERSISTENCE_PATH =
  { "repositor", "persistence", "postgres", "mysql", "sqlite", "mongo", "database", "/db/", "infrastructure" }

---@param target AgentTarget
---@param T string?
---@return boolean
local function is_persistence(target, T)
  if
    T
    and (
      names.looks_like_implementation(T)
      or T:lower():find "repositor"
      or T:lower():find "store"
      or T:lower():find "dao"
    )
  then
    return true
  end
  if layers.of(target.path) == "infrastructure" then
    return true
  end
  local lower = target.path:lower()
  for _, p in ipairs(PERSISTENCE_PATH) do
    if lower:find(p, 1, true) then
      return true
    end
  end
  return false
end

return {
  cap = 2600,
  stability = 2,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local T, ext = contracts.subject(target)
    if not is_persistence(target, T) then
      return done(nil)
    end
    local entity = T and names.entity_of(T)
    if not entity then
      return done(nil)
    end
    local root = index.root(target.buf)
    local specs = vim.tbl_map(function(i)
      return i.spec
    end, imports.extract(vim.api.nvim_buf_get_lines(target.buf, 0, -1, false), ext))

    schema.find(root, entity, function(found)
      local schema_text = found
          and table.concat(
            vim.tbl_map(function(t)
              return table.concat(t.lines, "\n")
            end, found.tables),
            "\n"
          )
        or nil
      local env = schema.environment(root, ext, schema_text, specs)
      if not found and not env.dialect then
        return done(nil)
      end
      local lines = { env.line }
      if found then
        for _, t in ipairs(found.tables) do
          lines[#lines + 1] = ("schema (%s:%d)"):format(t.path:sub(#root + 2), t.line)
          vim.list_extend(lines, t.lines)
        end
        if #found.changes > 0 then
          lines[#lines + 1] = "later changes:"
          vim.list_extend(lines, found.changes)
        end
      else
        lines[#lines + 1] = ("no table definition found for %s (searched *.sql and *.prisma): take the columns from the entity's fields; do not invent others"):format(
          entity
        )
      end
      done(table.concat(lines, "\n"))
    end)
  end,
}
