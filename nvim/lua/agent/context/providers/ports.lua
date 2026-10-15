-- `ports` provider: for an application service, the ports (interfaces) it receives, with their real signatures, and, when
-- implementing, another service from the project as a style example. Silent if the code is not a service.
local contracts = require "agent.repository.contracts"
local discovery = require "agent.discovery"
local index = require "agent.ddd.index"
local ports = require "agent.service.ports"

return {
  cap = 3200,
  stability = 2,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  ---@param ctx { names: string[], action: table }?
  collect = function(target, done, ctx)
    local T, ext = contracts.subject(target)
    if not (T and ports.looks_like_service(T, target.path)) then
      return done(nil)
    end
    local root = index.root(target.buf)

    ports.dependencies(root, target, T, ext, function(list)
      local lines = {}
      for _, p in ipairs(list) do
        lines[#lines + 1] = ("port %s (%s:%d): call only these methods"):format(
          p.name,
          discovery.rel(p.path, root),
          p.line
        )
        vim.list_extend(lines, p.lines)
      end

      local function finish()
        done(#lines > 0 and table.concat(lines, "\n") or nil)
      end
      if not (ctx and ctx.action and ctx.action.examples) then
        return finish()
      end
      contracts.sibling(root, target, T, ext, {}, function(sibling)
        if sibling and sibling.method_lines then
          lines[#lines + 1] = ("example method %s, from %s (%s): follow its structure and error handling"):format(
            sibling.method,
            sibling.type,
            discovery.rel(sibling.path, root)
          )
          vim.list_extend(lines, sibling.method_lines)
        end
        finish()
      end, "(Service|UseCase|Interactor|Handler|Manager)")
    end)
  end,
}
