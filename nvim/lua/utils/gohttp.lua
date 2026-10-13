-- ── Go: handlers HTTP a partir de la interfaz del servicio (sin LLM, 0 tokens) ─
-- Un handler (`type NoteHandler struct { svc application.NoteService }`) casi siempre repite la forma de su servicio: leer
-- el id de la ruta, decodificar el cuerpo, llamar, responder. Con el struct escrito:
--   func (h *NoteHandler) |   → un handler por cada método del servicio que aún no tiene, y `Routes` con sus rutas
--   func |  (columna 0)       → lo mismo con el receptor ya escrito
-- El framework sale de go.mod: net/http (Go ≥ 1.22, PathValue), chi, gin o echo. Reglas (por el nombre y los parámetros):
--   verbo: Get/Find/List/Search → GET · Create/Add → POST · Update → PUT · Set*/Patch* → PATCH · Delete/Remove → DELETE
--   `id` (string, o acaba en ID) → parámetro de ruta; un struct en un GET (`filter ListFilter`) → query string campo a campo;
--   el resto → cuerpo JSON (struct anónimo con tags en snake_case, o el struct tal cual si el servicio recibe uno)
--   (T, error) → 200 con el JSON (201 en POST); solo error → 204. Errores: `writeError` (helpers opcionales: ítem aparte).
-- Fiber u otros routers: sin ítems (no se inventa).
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local HANDLER_SUFFIXES = { "Handler", "Handlers", "Controller", "Resource", "API", "Api" }

---@param name string
---@return boolean
local function is_handler(name)
  for _, s in ipairs(HANDLER_SUFFIXES) do
    if #name > #s and name:sub(-#s) == s then
      return true
    end
  end
  return false
end

---@param path string
---@return "nethttp"|"chi"|"gin"|"echo"|nil
local function framework(path)
  local gomod = vim.fs.find("go.mod", { path = vim.fs.dirname(path), upward = true })[1]
  if not gomod then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, gomod)
  local text = ok and table.concat(lines, "\n") or ""
  if text:find("go-chi/chi", 1, true) then
    return "chi"
  elseif text:find("gin-gonic/gin", 1, true) then
    return "gin"
  elseif text:find("labstack/echo", 1, true) then
    return "echo"
  elseif text:find("gofiber/fiber", 1, true) then
    return nil
  end
  local minor = text:match "\ngo%s+1%.(%d+)"
  return (tonumber(minor) or 0) >= 22 and "nethttp" or nil
end

---@param t string
---@return boolean
local function is_context(t)
  return t == "context.Context"
end

--- Verbo HTTP y sufijo de ruta por el nombre del método del servicio
---@param name string
---@return string verb, string? action
local function verb_of(name)
  for _, p in ipairs { "Get", "Find", "List", "Search", "Fetch", "Read" } do
    if name:sub(1, #p) == p then
      return "GET"
    end
  end
  for _, p in ipairs { "Create", "Add", "Register", "Insert" } do
    if name:sub(1, #p) == p then
      return "POST"
    end
  end
  if name:sub(1, 6) == "Update" or name:sub(1, 7) == "Replace" then
    return "PUT"
  end
  for _, p in ipairs { "Set", "Patch", "Mark", "Toggle", "Archive", "Complete" } do
    if name:sub(1, #p) == p then
      return "PATCH", require("utils.gotags").snake((name:gsub("^" .. p, "")))
    end
  end
  if name:sub(1, 6) == "Delete" or name:sub(1, 6) == "Remove" then
    return "DELETE"
  end
  return "POST", require("utils.gotags").snake(name)
end

---@param name string
---@return boolean
local function is_id(p)
  return p.type == "string" and (p.name == "id" or (p.name and p.name:match "I[dD]$") ~= nil)
end

---@param base string
---@return string
local function plural(base)
  local s = require("utils.gotags").snake(base):gsub("_", "-")
  if s:match "[^aeiou]y$" then
    return s:sub(1, -2) .. "ies"
  elseif s:match "[sxz]$" or s:match "[cs]h$" then
    return s .. "es"
  end
  return s .. "s"
end

-- ── lo que cambia por framework ──────────────────────────────────────────────

---@class GoHttpFw
---@field sig string
---@field ctx string
---@field path fun(name: string): string
---@field query_setup string?
---@field query fun(key: string): string
---@field decode fun(var: string): string  condición `err := ...; err != nil` completa
---@field bad fun(err: string): string[]
---@field fail fun(err: string): string[]
---@field ok fun(status: string, value: string): string[]
---@field empty fun(): string[]
local FW = {
  nethttp = {
    sig = "(w http.ResponseWriter, r *http.Request)",
    ctx = "r.Context()",
    path = function(n)
      return ('r.PathValue("%s")'):format(n)
    end,
    query_setup = "q := r.URL.Query()",
    query = function(k)
      return ('q.Get("%s")'):format(k)
    end,
    decode = function(v)
      return ("json.NewDecoder(r.Body).Decode(&%s)"):format(v)
    end,
    bad = function(e)
      return { ("http.Error(w, %s.Error(), http.StatusBadRequest)"):format(e), "return" }
    end,
    fail = function(e)
      return { ("writeError(w, %s)"):format(e), "return" }
    end,
    ok = function(status, v)
      return { ("writeJSON(w, %s, %s)"):format(status, v) }
    end,
    empty = function()
      return { "w.WriteHeader(http.StatusNoContent)" }
    end,
  },
  gin = {
    sig = "(c *gin.Context)",
    ctx = "c.Request.Context()",
    path = function(n)
      return ('c.Param("%s")'):format(n)
    end,
    query = function(k)
      return ('c.Query("%s")'):format(k)
    end,
    decode = function(v)
      return ("c.ShouldBindJSON(&%s)"):format(v)
    end,
    bad = function(e)
      return { ('c.JSON(http.StatusBadRequest, gin.H{"error": %s.Error()})'):format(e), "return" }
    end,
    fail = function(e)
      return { ('c.JSON(http.StatusInternalServerError, gin.H{"error": %s.Error()})'):format(e), "return" }
    end,
    ok = function(status, v)
      return { ("c.JSON(%s, %s)"):format(status, v) }
    end,
    empty = function()
      return { "c.Status(http.StatusNoContent)" }
    end,
  },
  echo = {
    sig = "(c echo.Context) error",
    ctx = "c.Request().Context()",
    path = function(n)
      return ('c.Param("%s")'):format(n)
    end,
    query = function(k)
      return ('c.QueryParam("%s")'):format(k)
    end,
    decode = function(v)
      return ("c.Bind(&%s)"):format(v)
    end,
    bad = function(e)
      return { ("return echo.NewHTTPError(http.StatusBadRequest, %s.Error())"):format(e) }
    end,
    fail = function(e)
      return { ("return %s"):format(e) }
    end,
    ok = function(status, v)
      return { ("return c.JSON(%s, %s)"):format(status, v) }
    end,
    empty = function()
      return { "return c.NoContent(http.StatusNoContent)" }
    end,
  },
}
FW.chi = vim.tbl_extend("force", FW.nethttp, {
  path = function(n)
    return ('chi.URLParam(r, "%s")'):format(n)
  end,
})

---@param t string
---@return string
local function status_const(verb)
  return verb == "POST" and "http.StatusCreated" or "http.StatusOK"
end

--- Cuerpo de un handler
---@param fw GoHttpFw
---@param m GoImplMethod
---@param field string  campo del servicio (`svc`)
---@param recv string
---@param pkg GoImplPackage
---@param path string
---@return string[] lines (sin sangría), string verb
local function body_of(fw, m, field, recv, pkg, path, fw_name)
  local verb = verb_of(m.name)
  local lines, args = {}, {}
  local function push(...)
    for _, l in ipairs { ... } do
      lines[#lines + 1] = l
    end
  end
  local function push_all(list)
    for _, l in ipairs(list) do
      lines[#lines + 1] = l
    end
  end
  local is_echo = fw_name == "echo"
  local function block(cond, on_fail)
    push(("if err := %s; err != nil {"):format(cond))
    for _, l in ipairs(on_fail) do
      push("\t" .. l)
    end
    push "}"
  end

  local body_fields, query_param = {}, nil
  local used_query = false
  for i, p in ipairs(m.params) do
    local pname = p.name or ("arg" .. i)
    if i == 1 and is_context(p.type) then
      args[#args + 1] = fw.ctx
    elseif is_id(p) then
      push(("%s := %s"):format(pname, fw.path(pname)))
      args[#args + 1] = pname
    elseif verb == "GET" and not p.type:match "^[%*%[]" and not ix.BUILTIN[p.type] then
      -- struct de filtro en un GET: campo a campo desde la query
      local info = ix.resolve_struct(p.type, pkg, path)
      query_param = { name = pname, type = p.type, fields = info and info.fields or {} }
      args[#args + 1] = pname
    elseif verb == "GET" then
      -- parámetro simple en un GET: query string
      if fw.query_setup and not used_query then
        push(fw.query_setup)
        used_query = true
      end
      push(("%s := %s"):format(pname, fw.query(require("utils.gotags").snake(pname))))
      args[#args + 1] = pname
    elseif not ix.BUILTIN[p.type] and not p.type:match "^[%*%[]" then
      -- el servicio recibe un struct: ese es el cuerpo
      push(("var %s %s"):format(pname, p.type))
      block(fw.decode(pname), fw.bad "err")
      args[#args + 1] = pname
    else
      body_fields[#body_fields + 1] = { name = pname, type = p.type }
      args[#args + 1] = "body." .. (pname:gsub("^%l", string.upper))
    end
  end

  if query_param then
    if fw.query_setup and not used_query then
      push(fw.query_setup)
    end
    local lits, post = {}, {}
    for _, f in ipairs(query_param.fields) do
      local key = require("utils.gotags").snake(f.name)
      local get = fw.query(key)
      if f.type == "string" then
        lits[#lits + 1] = ("\t%s: %s,"):format(f.name, get)
      elseif f.type:match "^u?int%d*$" then
        post[#post + 1] = ('if v := %s; v != "" {'):format(get)
        post[#post + 1] = "\tn, err := strconv.Atoi(v)"
        post[#post + 1] = "\tif err != nil {"
        for _, l in ipairs(fw.bad "err") do
          post[#post + 1] = "\t\t" .. l
        end
        post[#post + 1] = "\t}"
        post[#post + 1] = ("\t%s.%s = %s"):format(
          query_param.name,
          f.name,
          f.type == "int" and "n" or (f.type .. "(n)")
        )
        post[#post + 1] = "}"
      elseif f.type == "*bool" or f.type == "bool" then
        post[#post + 1] = ('if v := %s; v != "" {'):format(get)
        post[#post + 1] = "\tb, err := strconv.ParseBool(v)"
        post[#post + 1] = "\tif err != nil {"
        for _, l in ipairs(fw.bad "err") do
          post[#post + 1] = "\t\t" .. l
        end
        post[#post + 1] = "\t}"
        post[#post + 1] = ("\t%s.%s = %s"):format(query_param.name, f.name, f.type == "*bool" and "&b" or "b")
        post[#post + 1] = "}"
      else
        lits[#lits + 1] = ("\t// TODO: %s (%s) from the query string"):format(f.name, f.type)
      end
    end
    if #lits > 0 then
      push(("%s := %s{"):format(query_param.name, query_param.type))
      push_all(lits)
      push "}"
    else
      push(("%s := %s{}"):format(query_param.name, query_param.type))
    end
    push_all(post)
  end

  if #body_fields > 0 then
    push "var body struct {"
    for _, f in ipairs(body_fields) do
      push(
        ("\t%s %s `json:%q`"):format((f.name:gsub("^%l", string.upper)), f.type, require("utils.gotags").snake(f.name))
      )
    end
    push "}"
    block(fw.decode "body", fw.bad "err")
  end

  local call = ("%s.%s.%s(%s)"):format(recv, field, m.name, table.concat(args, ", "))
  local last = m.results[#m.results]
  if #m.results >= 2 and last == "error" then
    push(("res, err := %s"):format(call))
    push "if err != nil {"
    for _, l in ipairs(fw.fail "err") do
      push("\t" .. l)
    end
    push "}"
    push_all(fw.ok(status_const(verb), "res"))
  elseif #m.results == 1 and last == "error" then
    block(call, fw.fail "err")
    push_all(fw.empty())
  else
    push(call)
    push_all(fw.empty())
  end
  if is_echo then
    -- echo devuelve error en cada camino: el último `return` ya está dentro de ok/empty
  end
  return lines, verb
end

---@param s string
---@return string
local function esc(s)
  return ix.esc(s)
end

--- Ítems de handlers para `struct` (handler) según sus servicios
---@param pkg GoImplPackage
---@param path string
---@param struct string
---@param recv string
---@param ptr boolean
---@param header boolean
---@param range table
---@param order integer
---@return table[]
local function items_for(pkg, path, struct, recv, ptr, header, range, order)
  local fw_name = framework(path)
  local fw = fw_name and FW[fw_name]
  if not fw then
    return {}
  end
  local have = ix.defined_methods(pkg, struct)
  local items = {}
  local recv_text = ("(%s %s%s)"):format(recv, ptr and "*" or "", struct)

  for _, f in ipairs(pkg.structs[struct] or {}) do
    local methods = ix.resolve_interface(f.type, pkg, path)
    if methods then
      local service = f.type:match "([%w_]+)$"
      local resource = plural((service:gsub("Service$", ""):gsub("UseCase$", "")))
      local missing, routes = {}, {}
      for _, m in ipairs(methods) do
        local verb, action = verb_of(m.name)
        local id_param
        for _, p in ipairs(m.params) do
          if is_id(p) then
            id_param = p.name
          end
        end
        local suffix = (id_param and (fw_name == "nethttp" or fw_name == "chi") and ("/{" .. id_param .. "}") or "")
          .. (id_param and (fw_name == "gin" or fw_name == "echo") and ("/:" .. id_param) or "")
          .. (action and ("/" .. action) or "")
        routes[#routes + 1] = { method = m.name, verb = verb, path = "/" .. resource .. suffix }
        if not have[m.name] then
          missing[#missing + 1] = m
        end
      end

      local function method_text(m, with_header, stop)
        local lines = body_of(fw, m, f.name, recv, pkg, path, fw_name)
        local indented = {}
        for _, l in ipairs(lines) do
          indented[#indented + 1] = "\t" .. l
        end
        local head = (with_header and ("func " .. recv_text .. " ") or "") .. m.name .. fw.sig .. " {\n"
        local text = head .. table.concat(indented, "\n") .. "\n}"
        return text
      end

      local texts = {}
      for _, m in ipairs(missing) do
        local text = method_text(m, header)
        -- en el ítem de "todos", el primero va sin cabecera si el cursor ya está tras el receptor
        texts[#texts + 1] = method_text(m, header or #texts > 0)
        items[#items + 1] = {
          label = header and ("func %s %s"):format(recv_text, m.name) or m.name,
          labelDetails = { description = ("%s · %s"):format(service, (verb_of(m.name))) },
          kind = KIND.Method,
          insertTextFormat = FORMAT.Snippet,
          filterText = header and ("func method %s %s"):format(struct, m.name) or m.name,
          sortText = ("%03d"):format(order + #items + 1),
          documentation = { kind = "markdown", value = "```go\n" .. text .. "\n```" },
          textEdit = { newText = esc(text) .. "$0", range = range },
        }
      end

      if not have.Routes then
        local reg = {}
        for _, r in ipairs(routes) do
          if fw_name == "nethttp" then
            reg[#reg + 1] = ('\tmux.HandleFunc("%s %s", %s.%s)'):format(r.verb, r.path, recv, r.method)
          elseif fw_name == "chi" then
            reg[#reg + 1] = ('\tr.%s("%s", %s.%s)'):format(
              r.verb:sub(1, 1) .. r.verb:sub(2):lower(),
              r.path,
              recv,
              r.method
            )
          else
            reg[#reg + 1] = ('\tr.%s("%s", %s.%s)'):format(r.verb, r.path, recv, r.method)
          end
        end
        local arg = ({
          nethttp = "mux *http.ServeMux",
          chi = "r chi.Router",
          gin = "r gin.IRouter",
          echo = "r *echo.Echo",
        })[fw_name]
        local text = ("%sRoutes(%s) {\n%s\n}"):format(
          header and ("func " .. recv_text .. " ") or "",
          arg,
          table.concat(reg, "\n")
        )
        table.insert(items, 1, {
          label = header and ("func %s Routes"):format(recv_text) or "Routes",
          labelDetails = { description = ("%s · %d routes"):format(service, #routes) },
          kind = KIND.Method,
          insertTextFormat = FORMAT.Snippet,
          filterText = header and ("func method %s Routes"):format(struct) or "Routes",
          sortText = ("%03d"):format(order),
          documentation = { kind = "markdown", value = "```go\n" .. text .. "\n```" },
          textEdit = { newText = esc(text), range = range },
        })
      end

      if #missing > 1 then
        table.insert(items, 1, {
          label = header and ("func %s …all handlers (%d)"):format(recv_text, #missing)
            or ("…all handlers (%d)"):format(#missing),
          labelDetails = { description = service },
          kind = KIND.Method,
          insertTextFormat = FORMAT.Snippet,
          filterText = header and ("func method %s all handlers"):format(struct) or "all handlers",
          sortText = ("%03d"):format(order),
          documentation = { kind = "markdown", value = "```go\n" .. table.concat(texts, "\n\n") .. "\n```" },
          textEdit = { newText = esc(table.concat(texts, "\n\n")), range = range },
        })
      end
    end
  end

  -- helpers de respuesta para net/http y chi
  if (fw_name == "nethttp" or fw_name == "chi") and header then
    local funcs = {}
    for _, fn in ipairs(pkg.funcs) do
      funcs[fn.name] = true
    end
    if not (funcs.writeJSON and funcs.writeError) and #items > 0 then
      local text = table.concat({
        "func writeJSON(w http.ResponseWriter, status int, v any) {",
        '\tw.Header().Set("Content-Type", "application/json")',
        "\tw.WriteHeader(status)",
        "\t_ = json.NewEncoder(w).Encode(v)",
        "}",
        "",
        "func writeError(w http.ResponseWriter, err error) {",
        "\t// TODO: map domain errors to status codes (errors.Is(err, domain.ErrNotFound) → 404)",
        '\twriteJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})',
        "}",
      }, "\n")
      items[#items + 1] = {
        label = "func …handler helpers (writeJSON, writeError)",
        labelDetails = { description = fw_name },
        kind = KIND.Snippet,
        insertTextFormat = FORMAT.Snippet,
        filterText = "func handler helpers writeJSON writeError",
        sortText = ("%03d"):format(order + #items + 1),
        documentation = { kind = "markdown", value = "```go\n" .. text .. "\n```" },
        textEdit = { newText = esc(text), range = range },
      }
    end
  end
  return items
end

---@param ctx { line: string, cursor: integer[] }
---@return table[]
function M.method_items(ctx)
  local struct, frag, from, receiver = require("utils.goimpl").method_position(ctx.line, ctx.cursor[2])
  if not struct or not is_handler(struct) then
    return {}
  end
  local pkg, path = ix.current_package()
  if not pkg or not pkg.structs[struct] then
    return {}
  end
  local range = ix.range_of(ctx.cursor[1], from, ctx.cursor[2])
  local recv = receiver.var ~= "" and receiver.var or ix.receiver_name(struct)
  local items = items_for(pkg, path, struct, recv, receiver.ptr, false, range, 0)
  return vim.tbl_filter(function(it)
    return frag == "" or it.filterText:lower():sub(1, #frag) == frag:lower()
  end, items)
end

---@param range table
---@param frag string
---@return table[]
function M.declaration_items(range, frag)
  local pkg, path = ix.current_package()
  if not pkg then
    return {}
  end
  local _, src = ix.buffer_state()
  local items = {}
  local names = vim.tbl_keys(pkg.structs)
  table.sort(names)
  for _, struct in ipairs(names) do
    if is_handler(struct) and src:find("type%s+" .. struct .. "%s+struct") then
      local first
      for _, m in ipairs(pkg.methods) do
        if m.recv == struct then
          first = first or m
        end
      end
      local recv = first and first.var or ix.receiver_name(struct)
      vim.list_extend(items, items_for(pkg, path, struct, recv, first == nil or first.ptr, true, range, #items))
    end
  end
  return vim.tbl_filter(function(it)
    return frag == "" or ("func"):find(frag:lower(), 1, true) == 1 or it.filterText:lower():find(frag:lower(), 1, true)
  end, items)
end

return M
