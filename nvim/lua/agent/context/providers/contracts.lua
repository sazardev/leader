-- `contracts` provider: if the target is (or is inside) an adapter, it gives it the PORT it must fulfil, which
-- of that port's methods already exist and which are missing, and, if the action is an implement one, another implementation
-- from the project as a style example (constructor, errors, mapping). Silent if the code is not an adapter.
local contracts = require "agent.repository.contracts"
local discovery = require "agent.discovery"
local names = require "agent.repository.contracts.names"
local index = require "agent.ddd.index"

---@param path string
---@return string  path relative to the project
local function rel(path, root)
  return path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2) or path
end

return {
  cap = 3200,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  ---@param ctx { names: string[], action: table }?
  collect = function(target, done, ctx)
    local T, ext = contracts.subject(target)
    if not T then
      return done(nil)
    end
    local explicit = contracts.explicit_ports(target, T)
    if #explicit == 0 and not names.looks_like_implementation(T) then
      return done(nil) -- does not look like an adapter: not even one search is paid for
    end
    local root = index.root(target.buf)

    contracts.find_port(root, target, T, function(port)
      if not port then
        return done(nil)
      end
      local implemented, has_ctor = contracts.implemented(target, T, ext)
      local missing, present = {}, {}
      for _, m in ipairs(port.methods) do
        if implemented[m] or implemented[m:sub(1, 1):lower() .. m:sub(2)] then
          present[#present + 1] = m
        else
          missing[#missing + 1] = m
        end
      end

      local lines = { ("port %s (%s:%d)"):format(port.name, rel(port.path, root), port.line) }
      vim.list_extend(lines, port.lines)
      lines[#lines + 1] = ("%s: implemented %s · missing %s%s"):format(
        T,
        #present > 0 and table.concat(present, ", ") or "none",
        #missing > 0 and table.concat(missing, ", ") or "none",
        ext == "go"
            and (has_ctor and " · constructor: present" or (" · constructor: missing (New%s)"):format(
              T:sub(1, 1):upper() .. T:sub(2)
            ))
          or ""
      )

      -- the types the port names (the entity it persists and what it returns) that do NOT appear in the target:
      -- without them the model guesses the fields
      local wanted, seen = {}, { [T] = true, [port.name] = true }
      local entity = names.entity_of(T)
      if entity then
        wanted[1], seen[entity] = entity, true
      end
      for word in table.concat(port.lines, "\n"):gmatch "%f[%w_]%u[%w_]*" do
        if not seen[word] and #wanted < 3 and word ~= "Context" and word ~= "Error" then
          seen[word] = true
          wanted[#wanted + 1] = word
        end
      end

      local function finish()
        if not (ctx and ctx.action and ctx.action.examples) then
          return done(table.concat(lines, "\n"))
        end
        -- style example from another implementation in the project
        contracts.sibling(root, target, T, ext, #missing > 0 and missing or port.methods, function(sibling)
          if sibling then
            if sibling.ctor_lines then
              lines[#lines + 1] = ("example constructor, from %s (%s)"):format(sibling.type, rel(sibling.path, root))
              vim.list_extend(lines, sibling.ctor_lines)
            end
            if sibling.method_lines then
              lines[#lines + 1] = ("example method %s, from %s (%s): follow its structure, error handling and mapping"):format(
                sibling.method,
                sibling.type,
                rel(sibling.path, root)
              )
              vim.list_extend(lines, sibling.method_lines)
            end
          end
          done(table.concat(lines, "\n"))
        end)
      end

      local pending = #wanted
      if pending == 0 then
        return finish()
      end
      for _, name in ipairs(wanted) do
        discovery.find_type(root, name, ext, function(found)
          if found then
            lines[#lines + 1] = ("%s (%s:%d)"):format(found.name, rel(found.path, root), found.line)
            vim.list_extend(lines, found.lines)
          end
          pending = pending - 1
          if pending == 0 then
            finish()
          end
        end)
      end
    end)
  end,
}
