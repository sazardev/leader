-- Proveedor `contracts`: si el objetivo es (o está dentro de) un adaptador, le da el PUERTO que debe cumplir, qué
-- métodos de ese puerto ya existen y cuáles faltan, y —si la acción es de implementar— otra implementación del
-- proyecto como ejemplo de estilo (constructor, errores, mapeo). Silencioso si el código no es un adaptador.
local contracts = require "agent.repository.contracts"
local discovery = require "agent.discovery"
local names = require "agent.repository.contracts.names"
local index = require "agent.ddd.index"

---@param path string
---@return string  ruta relativa al proyecto
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
      return done(nil) -- no parece un adaptador: no se paga ni una búsqueda
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

      -- los tipos que el puerto nombra (la entidad que persiste y lo que devuelve) y que NO aparecen en el objetivo:
      -- sin ellos el modelo adivina los campos
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
        -- ejemplo de estilo de otra implementación del proyecto
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
