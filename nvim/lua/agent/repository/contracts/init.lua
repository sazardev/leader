-- ── Contratos: el puerto que un tipo implementa, lo que le falta y un ejemplo hermano ────────────────
-- Para implementar un repositorio (o cualquier adaptador) el modelo necesita TRES cosas que no están en el
-- archivo que ves: la interfaz que debe cumplir, qué métodos de esa interfaz ya existen y cuáles faltan, y cómo
-- se escribió otro adaptador del mismo tipo en este proyecto. Todo se busca solo, en cualquier lenguaje, con
-- ripgrep (nombres) y treesitter (declaraciones); nada depende de que las carpetas se llamen de una forma.
local discovery = require "agent.discovery"
local names = require "agent.repository.contracts.names"
local scopes = require "agent.context.scopes"

local M = {}

---@param target AgentTarget
---@return string? name, string? ext
function M.subject(target)
  local ext = target.path:match "%.([%w]+)$" or ""
  if target.kind == "class" and target.name then
    return target.name, ext
  end
  -- método de Go: el receptor es el tipo
  for _, l in ipairs(target.lines) do
    local receiver = l:match "^func%s*%(%s*[%w_]*%s*%*?%s*([%w_]+)"
    if receiver then
      return receiver, ext
    end
  end
  -- método de una clase (Python, TypeScript, Java, Rust `impl`...)
  local enclosing = scopes.enclosing(target.buf, target.first - 1, "class")
  return enclosing and enclosing.name or nil, ext
end

--- Puertos declarados a las claras (`implements X`, `class T(X)`, `impl X for T`, `var _ X = (*T)(nil)`)
---@param target AgentTarget
---@param T string
---@return string[]
function M.explicit_ports(target, T)
  local text = table.concat(vim.api.nvim_buf_get_lines(target.buf, 0, -1, false), "\n")
  local found = {}
  local function add(list)
    for name in list:gmatch "[%w_]+" do
      if
        name ~= T
        and name ~= "extends"
        and name ~= "implements"
        and name ~= "object"
        and name ~= "ABC"
        and name ~= "Protocol"
      then
        found[#found + 1] = name
      end
    end
  end
  for list in text:gmatch("[%w_%s<>,]-%f[%w_]" .. T .. "%f[^%w_][^{\n]-implements%s+([%w_,%s%.<>]+)") do
    add(list)
  end
  local py = text:match("class%s+" .. T .. "%s*%(([^)]*)%)")
  if py then
    add(py)
  end
  local rs = text:match("impl%s+([%w_]+)%s+for%s+" .. T .. "%f[^%w_]")
  if rs then
    found[#found + 1] = rs
  end
  local go = text:match("var%s+_%s+[%w_]*%.?([%w_]+)%s*=%s*%(?%*?%s*" .. T)
  if go then
    found[#found + 1] = go
  end
  return found
end

---@param lines string[]
---@param ext string
---@return string[]
function M.port_methods(lines, ext)
  local out, seen = {}, {}
  for i, l in ipairs(lines) do
    local name
    if ext == "py" then
      name = l:match "^%s*def%s+([%w_]+)"
    elseif ext == "rs" then
      name = l:match "^%s*fn%s+([%w_]+)"
    elseif i > 1 and not l:match "^%s*[@/%*]" then
      name = l:match "([%w_]+)%s*%b()" or l:match "([%w_]+)%s*<[^>]*>%s*%b()"
    end
    if name and not seen[name] and name ~= "interface" and name ~= "function" then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

--- Métodos que `T` ya implementa. Go: funciones con ese receptor en el paquete (los métodos viven fuera del tipo);
--- el resto: los que están declarados dentro de la clase/impl.
---@param target AgentTarget
---@param T string
---@param ext string
---@return table<string, boolean> implemented, boolean has_constructor
function M.implemented(target, T, ext)
  local set, ctor = {}, false
  local function scan(text)
    if ext == "go" then
      for name in text:gmatch("func%s*%(%s*[%w_]*%s*%*?%s*" .. T .. "%s*%)%s*([%w_]+)") do
        set[name] = true
      end
      if
        text:find("func%s+New[%w_]*%b()%s*%*?%s*" .. T .. "%f[^%w_]") or text:find("func%s+new" .. T .. "%f[^%w_]")
      then
        ctor = true
      end
    else
      for name in text:gmatch "fn%s+([%w_]+)" do
        set[name] = true
      end
      for name in text:gmatch "def%s+([%w_]+)" do
        set[name] = true
      end
      for name in text:gmatch "\n%s+[%w_%s<>%[%]]-%f[%w_]([%w_]+)%s*%b()%s*[:{%w]" do
        set[name] = true
      end
    end
  end
  if ext == "go" then
    local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(target.buf), ":h")
    local current = vim.api.nvim_buf_get_name(target.buf)
    for _, file in ipairs(vim.fn.glob(dir .. "/*.go", false, true)) do
      if file ~= current and not file:find "_test%.go$" then
        scan(table.concat(vim.fn.readfile(file), "\n"))
      end
    end
  end
  scan(table.concat(vim.api.nvim_buf_get_lines(target.buf, 0, -1, false), "\n"))
  return set, ctor
end

---@class AgentPort
---@field name string
---@field path string
---@field line integer
---@field lines string[]
---@field methods string[]
---@field ext string

--- Declaración completa del puerto en `path`, a partir de la línea donde ripgrep lo encontró
---@param hit { path: string, line: integer }
---@return AgentPort?
local function read_port(hit, name)
  if vim.fn.getfsize(hit.path) > 400000 then
    return nil
  end
  local ext = hit.path:match "%.([%w]+)$" or ""
  local lines = vim.fn.readfile(hit.path)
  local lang = discovery.lang_of(hit.path, ext)
  local first, last = hit.line, math.min(hit.line + 30, #lines)
  if lang then
    for _, d in ipairs(scopes.type_declarations(table.concat(lines, "\n"), lang)) do
      if d.first <= hit.line and hit.line <= d.last and not d.kind:find("impl", 1, true) then
        first, last = d.first, math.min(d.last, d.first + 40)
        break
      end
    end
  end
  local decl = vim.list_slice(lines, first, last)
  return { name = name, path = hit.path, line = first, lines = decl, methods = M.port_methods(decl, ext), ext = ext }
end

--- Encuentra el puerto que implementa `T`: primero los declarados a las claras, luego los que sugiere su nombre
---@param root string
---@param target AgentTarget
---@param T string
---@param cb fun(port: AgentPort?)
function M.find_port(root, target, T, cb)
  local candidates = M.explicit_ports(target, T)
  for _, c in ipairs(names.candidates(T)) do
    candidates[#candidates + 1] = c
  end
  if #candidates == 0 then
    return cb(nil)
  end
  candidates = vim.list_slice(candidates, 1, 5)
  local alternation = table.concat(candidates, "|")
  local regex = ("(type\\s+I?(%s)\\s+interface\\b|interface\\s+I?(%s)\\b|abstract\\s+class\\s+I?(%s)\\b|trait\\s+I?(%s)\\b|class\\s+I?(%s)\\s*\\(.*(Protocol|ABC))"):format(
    alternation,
    alternation,
    alternation,
    alternation,
    alternation
  )
  discovery.search(root, regex, nil, function(hits)
    for _, c in ipairs(candidates) do -- respeta el orden: lo explícito y lo específico primero
      for _, h in ipairs(hits) do
        if h.text:find("%f[%w_]I?" .. c .. "%f[^%w_]") then
          return cb(read_port(h, c))
        end
      end
    end
    cb(nil)
  end)
end

---@class AgentSibling
---@field type string
---@field path string
---@field method_lines string[]?
---@field method string?
---@field ctor_lines string[]?

--- Otra implementación del mismo tipo de adaptador (otro repositorio) y, de ella, un método y el constructor
---@param root string
---@param target AgentTarget
---@param T string
---@param ext string
---@param wanted string[] nombres de método que interesan (los que faltan), en orden
---@param cb fun(sibling: AgentSibling?)
---@param role_words string? alternancia de roles ("(Service|UseCase)"); por defecto, los de repositorio
function M.sibling(root, target, T, ext, wanted, cb, role_words)
  local roles = role_words or "(Repository|Repo|Store|Dao|Gateway|Storage)"
  local regex = ("(type\\s+\\w*%s\\w*\\s+struct|class\\s+\\w*%s\\w*|struct\\s+\\w*%s\\w*)"):format(roles, roles, roles)
  discovery.search(root, regex, { "-g", "*." .. ext }, function(hits)
    local here = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(target.buf), ":h")
    local best, best_score
    for _, h in ipairs(hits) do
      local name = h.text:match "type%s+([%w_]+)" or h.text:match "class%s+([%w_]+)" or h.text:match "struct%s+([%w_]+)"
      if name and name ~= T and not h.text:find "interface" and not h.text:find "abstract" then
        local score = (vim.fn.fnamemodify(h.path, ":h") == here and 2 or 0)
          + (names.looks_like_implementation(name) and 1 or 0)
        if not best or score > best_score then
          best, best_score = { name = name, hit = h }, score
        end
      end
    end
    if not best then
      return cb(nil)
    end
    local path = best.hit.path
    if vim.fn.getfsize(path) > 400000 then
      return cb(nil)
    end
    local lines = vim.fn.readfile(path)
    local lang = discovery.lang_of(path, ext)
    local sibling = { type = best.name, path = path }
    if lang then
      local fns = scopes.functions(table.concat(lines, "\n"), lang)
      local function belongs(f)
        if ext ~= "go" then
          return true
        end
        return (lines[f.first] or ""):find("%*?%s*" .. best.name .. "%s*%)") ~= nil
      end
      local pick
      for _, want in ipairs(wanted) do
        for _, f in ipairs(fns) do
          if f.name == want and belongs(f) then
            pick = pick or f
          end
        end
      end
      for _, f in ipairs(fns) do
        pick = pick or (belongs(f) and f.name and not f.name:find "^[Nn]ew" and f or nil)
      end
      if pick then
        sibling.method = pick.name
        sibling.method_lines = vim.list_slice(lines, pick.first, math.min(pick.last, pick.first + 30))
      end
      for _, f in ipairs(fns) do
        if f.name == "New" .. best.name and f.last - f.first < 14 then
          sibling.ctor_lines = vim.list_slice(lines, f.first, f.last)
        end
      end
    end
    cb(sibling)
  end)
end

return M
