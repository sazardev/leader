-- ── Repository check: does the adapter fulfil its port and its table? (0 tokens) ──
-- For the adapter under the cursor it compares, without an LLM:
--   · the port's methods with those the type already has (and the constructor);
--   · the entity's fields with the columns of its table (in the migrations or schema.prisma);
-- and shows the database in use and the sibling example that would be followed. A panel summarises the result.
local contracts = require "agent.repository.contracts"
local discovery = require "agent.discovery"
local index = require "agent.ddd.index"
local log = require "utils.log"
local names = require "agent.repository.contracts.names"
local panel = require "agent.ui.panel"
local schema = require "agent.repository.contracts.schema"
local target_mod = require "agent.context.target"

local M = {}

-- Lines of a table definition that are NOT columns
local NOT_COLUMN = {
  constraint = true,
  primary = true,
  unique = true,
  foreign = true,
  key = true,
  index = true,
  check = true,
  ["("] = true,
  [")"] = true,
}

---@param lines string[] CREATE TABLE block or Prisma `model`
---@return string[] column names in lowercase
function M.columns(lines)
  local out = {}
  for i, l in ipairs(lines) do
    if i > 1 then
      local word = l:match '^%s*["`%[]?([%w_]+)["`%]]?%s+[%w]'
      if word and not NOT_COLUMN[word:lower()] and not l:match "^%s*%)" then
        out[#out + 1] = word:lower()
      end
    end
  end
  return out
end

---@param lines string[] entity declaration
---@param ext string
---@return { name: string, key: string }[] fields with their normalised key (no underscores, lowercase)
function M.fields(lines, ext)
  local out = {}
  for i, l in ipairs(lines) do
    if i > 1 then
      local name
      if ext == "go" then
        name = l:match "^%s*([%u%l][%w_]*)%s+[%*%[%]%w%.]+"
      elseif ext == "rs" then
        name = l:match "^%s*pub%s+([%w_]+)%s*:" or l:match "^%s*([%w_]+)%s*:"
      elseif ext == "py" then
        name = l:match "^%s+([%a_][%w_]*)%s*:"
      elseif ext == "java" or ext == "kt" or ext == "cs" then
        name = l:match "^%s*[%a ]*[%w<>%[%]]+%s+([%a_][%w_]*)%s*[;=]"
          or l:match "^%s*val%s+([%w_]+)"
          or l:match "^%s*var%s+([%w_]+)"
      else
        name = l:match "^%s*[%a ]*([%a_][%w_]*)%??%s*:"
      end
      if name and name ~= "}" and not l:match "^%s*//" and not l:match "^%s*#" then
        out[#out + 1] = { name = name, key = name:lower():gsub("_", "") }
      end
    end
  end
  return out
end

function M.run()
  local buf = vim.api.nvim_get_current_buf()
  local target, err = target_mod.resolve(buf, "type", nil)
  if not target then
    return log.warn("Agent: " .. err)
  end
  local T, ext = contracts.subject(target)
  if not T then
    return log.warn "Agent: put the cursor on a repository adapter (its type or one of its methods)"
  end
  local root = index.root(buf)
  log.info "Repository: checking…"

  contracts.find_port(root, target, T, function(port)
    local entity = names.entity_of(T)
    local state = { T = T, ext = ext, port = port, entity = entity, root = root }

    local pending = 2
    local function done()
      pending = pending - 1
      if pending == 0 then
        local implemented, has_ctor = contracts.implemented(target, T, ext)
        local lines = M.report(state, implemented, has_ctor)
        panel.open(lines, ("Repository check · %s"):format(T))
      end
    end

    if entity then
      discovery.find_type(root, entity, ext, function(found)
        state.entity_decl = found
        done()
      end)
      schema.find(root, entity, function(found)
        state.schema = found
        done()
      end)
    else
      done()
      done()
    end
  end)
end

---@param state table
---@param implemented table<string, boolean>
---@param has_ctor boolean
---@return string[]
function M.report(state, implemented, has_ctor)
  local rel = function(p)
    return discovery.rel(p, state.root)
  end
  local lines = { ("# Repository check · %s"):format(state.T), "", "_Static analysis, **0 tokens**._", "" }

  lines[#lines + 1] = "## Port"
  lines[#lines + 1] = ""
  if not state.port then
    lines[#lines + 1] =
      "No port found for this type (looked for it by name and for `implements` / `impl X for` / `var _ X`)."
  else
    lines[#lines + 1] = ("`%s` in `%s:%d`"):format(state.port.name, rel(state.port.path), state.port.line)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| Method | Implemented |"
    lines[#lines + 1] = "|---|---|"
    for _, m in ipairs(state.port.methods) do
      local ok = implemented[m] or implemented[m:sub(1, 1):lower() .. m:sub(2)]
      lines[#lines + 1] = ("| %s | %s |"):format(m, ok and "✓" or "✗ missing")
    end
    if state.ext == "go" then
      lines[#lines + 1] = ("| constructor `New%s` | %s |"):format(state.T, has_ctor and "✓" or "✗ missing")
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = ("## Entity vs table%s"):format(state.entity and (" · " .. state.entity) or "")
  lines[#lines + 1] = ""
  local table_def = state.schema and state.schema.tables[1]
  if not state.entity then
    lines[#lines + 1] = "Could not tell which entity this repository persists (name it like `PostgresOrderRepository`)."
  elseif not state.entity_decl then
    lines[#lines + 1] = ("No definition of `%s` found in the project."):format(state.entity)
  elseif not table_def then
    lines[#lines + 1] = ("No table definition found for `%s` (searched `*.sql` and `*.prisma`)."):format(state.entity)
  else
    local cols, flds = M.columns(table_def.lines), M.fields(state.entity_decl.lines, state.ext)
    local colset, fieldset = {}, {}
    for _, c in ipairs(cols) do
      colset[c:gsub("_", "")] = c
    end
    local without_column, without_field = {}, {}
    for _, f in ipairs(flds) do
      fieldset[f.key] = true
      if not colset[f.key] then
        without_column[#without_column + 1] = f.name
      end
    end
    for _, c in ipairs(cols) do
      if not fieldset[(c:gsub("_", ""))] then
        without_field[#without_field + 1] = c
      end
    end
    lines[#lines + 1] = ("Table in `%s:%d` · entity in `%s:%d`"):format(
      rel(table_def.path),
      table_def.line,
      rel(state.entity_decl.path),
      state.entity_decl.line
    )
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("- **Entity fields without a column** (%d): %s"):format(
      #without_column,
      #without_column > 0 and table.concat(without_column, ", ") or "none ✓"
    )
    lines[#lines + 1] = ("- **Columns without an entity field** (%d): %s"):format(
      #without_field,
      #without_field > 0 and table.concat(without_field, ", ") or "none ✓"
    )
    if #without_column + #without_field > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] =
        "_Names are compared ignoring case and underscores (`TotalCents` ↔ `total_cents`). A mismatch can be a rename or a missing migration or field._"
    end
  end
  lines[#lines + 1] = ""
  return lines
end

return M
