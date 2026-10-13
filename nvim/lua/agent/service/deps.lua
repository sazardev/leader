-- ── Service deps: do the service's dependencies exist, are they called correctly and are they wired? (0 tokens) ───
-- For the service under the cursor, no LLM: for each port it receives, which methods it declares, which ones this file calls
-- (and which it calls without the port declaring them: it would not compile), which implementations it has and whether any is wired.
local contracts = require "agent.repository.contracts"
local discovery = require "agent.discovery"
local index = require "agent.ddd.index"
local log = require "utils.log"
local panel = require "agent.ui.panel"
local ports = require "agent.service.ports"
local scopes = require "agent.context.scopes"
local target_mod = require "agent.context.target"

local M = {}

--- How this file uses a port: the field that holds it, the methods it calls and the ones the port does not declare
---@param file_text string
---@param decl_text string  service declaration
---@param ctor string  constructor parameters
---@param p AgentDependency
---@return string? field, table<string, boolean> called, string[] unknown
function M.analyse(file_text, decl_text, ctor, p)
  local field = ports.field_name(decl_text, p.name) or ports.field_name(ctor, p.name)
  local called, unknown = {}, {}
  if field then
    for method in file_text:gmatch("[%.%s]" .. vim.pesc(field) .. "%.([%w_]+)%s*%(") do
      if not called[method] then
        called[method] = true
        if
          not vim.tbl_contains(p.methods, method)
          and not vim.tbl_contains(p.methods, method:sub(1, 1):upper() .. method:sub(2))
        then
          unknown[#unknown + 1] = method
        end
      end
    end
  end
  return field, called, unknown
end

function M.run()
  local buf = vim.api.nvim_get_current_buf()
  local target, err = target_mod.resolve(buf, "type", nil)
  if not target then
    return log.warn("Agent: " .. err)
  end
  local T, ext = contracts.subject(target)
  if not T then
    return log.warn "Agent: put the cursor on a service (its type or one of its methods)"
  end
  local root = index.root(buf)
  log.info "Service: checking dependencies…"

  ports.dependencies(root, target, T, ext, function(list)
    local file_text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    local decl_text = ""
    for _, d in ipairs(scopes.type_declarations(buf)) do
      if d.name == T and not d.kind:find("impl", 1, true) then
        decl_text = table.concat(vim.api.nvim_buf_get_lines(buf, d.first - 1, d.last, false), "\n")
      end
    end
    local ctor = file_text:match("func%s+New" .. T .. "%s*(%b())") or ""

    local rows, pending = {}, #list
    if pending == 0 then
      return M.show(T, root, rows, ext)
    end
    for i, p in ipairs(list) do
      local field, called, unknown = M.analyse(file_text, decl_text, ctor, p)
      rows[i] = { port = p, field = field, called = called, unknown = unknown, impls = {} }

      discovery.implementations(root, p.name, ext, function(impls)
        rows[i].impls = impls
        local left = #impls
        if left == 0 then
          pending = pending - 1
          if pending == 0 then
            M.show(T, root, rows, ext)
          end
          return
        end
        for _, impl in ipairs(impls) do
          discovery.referenced_elsewhere(root, impl.name, impl.path, function(used)
            impl.wired = used
            left = left - 1
            if left == 0 then
              pending = pending - 1
              if pending == 0 then
                M.show(T, root, rows, ext)
              end
            end
          end)
        end
      end)
    end
  end)
end

---@param T string
---@param root string
---@param rows table[]
function M.show(T, root, rows)
  local lines = { ("# Service deps · %s"):format(T), "", "_Static analysis, **0 tokens**._", "" }
  if #rows == 0 then
    vim.list_extend(lines, {
      "No ports found: this service receives no interfaces from the project (looked at its fields, constructor and method parameters).",
    })
  else
    vim.list_extend(
      lines,
      { "| Port | Field | Calls here | Not in the port | Implementations | Wired |", "|---|---|---|---|---|---|" }
    )
    for _, r in ipairs(rows) do
      local calls = vim.tbl_keys(r.called)
      table.sort(calls)
      local impls, wired = {}, "–"
      for _, im in ipairs(r.impls) do
        impls[#impls + 1] = "`" .. im.name .. "`"
        wired = im.wired == true and "✓" or (im.wired == false and "✗" or "?")
      end
      lines[#lines + 1] = ("| `%s` (%s:%d) | %s | %s | %s | %s | %s |"):format(
        r.port.name,
        discovery.rel(r.port.path, root),
        r.port.line,
        r.field or "?",
        #calls > 0 and table.concat(calls, ", ") or "–",
        #r.unknown > 0 and ("**" .. table.concat(r.unknown, ", ") .. " ✗**") or "none ✓",
        #impls > 0 and table.concat(impls, ", ") or "✗ none",
        wired
      )
    end
    local problems = {}
    for _, r in ipairs(rows) do
      if #r.unknown > 0 then
        problems[#problems + 1] = ("- `%s` is called with `%s`, which `%s` does not declare: add it to the port or fix the call"):format(
          r.field or "?",
          table.concat(r.unknown, "`, `"),
          r.port.name
        )
      end
      if #r.impls == 0 then
        problems[#problems + 1] = ("- `%s` has no implementation in the project (try `<leader>aPp` on a new adapter)"):format(
          r.port.name
        )
      elseif r.impls[1].wired == false then
        problems[#problems + 1] = ("- `%s` is never used outside its own file: wire it in the composition root"):format(
          r.impls[1].name
        )
      end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## To attend"
    lines[#lines + 1] = ""
    if #problems == 0 then
      lines[#lines + 1] = "Nothing to attend ✓"
    else
      vim.list_extend(lines, problems)
    end
  end
  lines[#lines + 1] = ""
  panel.open(lines, ("Service deps · %s"):format(T))
end

return M
