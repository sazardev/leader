-- Definiciones de los TIPOS que usa el objetivo: es lo que evita que el modelo adivine los campos de
-- `Note` o los métodos de `Repo`. Independiente del lenguaje (queries `textobjects` de treesitter):
--   1. nombres de tipo del objetivo: nodos `*type_identifier*` y, donde no hay (Python, JS, Lua), los
--      identificadores en PascalCase;
--   2. si el tipo está en el MISMO archivo, se lee al instante con treesitter; si no, se pregunta al
--      LSP por su definición y se extrae del archivo de destino (solo del proyecto, no de dependencias);
--   3. los tipos de los campos de lo encontrado (`Tags []Tag`) se siguen un nivel, dentro del archivo;
--   4. si el objetivo es un método (Python/TS/Java...), la clase que lo contiene, sin el propio método.
-- Tope de tipos y de líneas por tipo: es contexto, no el repositorio.
local settings = require("core.settings").agent.context
local scopes = require "agent.context.scopes"

local IGNORED_PATHS = {
  "/node_modules/",
  "/vendor/",
  "/%.venv/",
  "/venv/",
  "/site%-packages/",
  "/%.cargo/",
  "/target/",
  "/pkg/mod/",
  "/dist/",
}

---@param name string
---@return boolean
local function pascal_case(name)
  return name:match "^[A-Z]" ~= nil and name:match "%l" ~= nil
end

---@param lines string[]
---@param limit integer
---@return string[]
local function clip(lines, limit)
  if #lines <= limit then
    return lines
  end
  local out = vim.list_slice(lines, 1, limit)
  out[#out + 1] = ("… (%d more lines)"):format(#lines - limit)
  return out
end

--- Mejor declaración de un nombre: una definición de tipo antes que un `impl`
---@param decls AgentTypeDecl[]
---@param name string
---@return AgentTypeDecl?
local function by_name(decls, name)
  local fallback
  for _, d in ipairs(decls) do
    if d.name == name then
      if not d.kind:find("impl", 1, true) then
        return d
      end
      fallback = fallback or d
    end
  end
  return fallback
end

---@param path string
---@return boolean
local function in_project(path, root)
  if root and path:sub(1, #root) ~= root then
    return false
  end
  for _, pattern in ipairs(IGNORED_PATHS) do
    if path:find(pattern) then
      return false
    end
  end
  return true
end

---@param location table  Location | LocationLink
---@return string?, integer?
local function location_of(location)
  local uri = location.uri or location.targetUri
  local range = location.range or location.targetSelectionRange or location.targetRange
  if not (uri and range) then
    return nil
  end
  return vim.uri_to_fname(uri), range.start.line
end

return {
  cap = 3500,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local root_node = scopes.parse(target.buf)
    if not root_node then
      return done(nil)
    end
    local node = root_node:named_descendant_for_range(target.first - 1, 0, target.last - 1, 1000)
    if not node then
      return done(nil)
    end

    local decls = scopes.type_declarations(target.buf)
    local entries, included = {}, {}
    local function overlaps_target(first, last)
      return first <= target.last and target.first <= last
    end

    ---@param name string
    ---@param header string
    ---@param lines string[]
    local function push(name, header, lines)
      if #entries < settings.types and not included[name] then
        included[name] = true
        entries[#entries + 1] = { name = name, header = header, lines = clip(lines, settings.type_lines) }
      end
    end

    local function push_local(decl)
      if decl.name and not overlaps_target(decl.first, decl.last) then
        local lines = vim.api.nvim_buf_get_lines(target.buf, decl.first - 1, decl.last, false)
        -- los valores de un tipo tipo-enum (Pending, Confirmed...) viven en un `const (...)` aparte
        for _, c in ipairs(scopes.constants_of(target.buf, nil, decl.name)) do
          if c.last - c.first < 15 and not overlaps_target(c.first, c.last) then
            lines = vim.list_extend(
              vim.list_extend(vim.list_slice(lines), { "" }),
              vim.api.nvim_buf_get_lines(target.buf, c.first - 1, c.last, false)
            )
          end
        end
        push(decl.name, ("%s (%s:%d)"):format(decl.name, vim.fn.fnamemodify(target.path, ":t"), decl.first), lines)
      end
    end

    -- 4. la clase que contiene al objetivo (métodos en Python/TS/Java/Rust)
    local enclosing = scopes.enclosing(target.buf, target.first - 1, "class")
    if enclosing and not (enclosing.first >= target.first and enclosing.last <= target.last) then
      local enclosing_decl
      for _, d in ipairs(decls) do
        if
          d.first <= enclosing.last
          and enclosing.first <= d.last
          and d.name
          and (not enclosing_decl or (d.last - d.first) <= (enclosing_decl.last - enclosing_decl.first))
        then
          enclosing_decl = d
        end
      end
      local struct = enclosing_decl
        and enclosing_decl.kind:find("impl", 1, true)
        and by_name(decls, enclosing_decl.name)
      if struct and not struct.kind:find("impl", 1, true) then
        push_local(struct) -- Rust: `impl Note` → la definición de `struct Note`
      elseif enclosing_decl then
        -- la clase entera menos el propio método (que ya va como objetivo)
        local before = vim.api.nvim_buf_get_lines(target.buf, enclosing.first - 1, target.first - 1, false)
        local after = vim.api.nvim_buf_get_lines(target.buf, target.last, enclosing.last, false)
        local lines = vim.list_extend(before, { "…" })
        push(
          enclosing_decl.name,
          ("%s (%s:%d)"):format(enclosing_decl.name, vim.fn.fnamemodify(target.path, ":t"), enclosing.first),
          vim.list_extend(lines, after)
        )
      end
    end

    -- 1-2. tipos usados por el objetivo
    local pending_lsp = {}
    local seen_names = {}
    for _, n in ipairs(scopes.type_names(node, target.buf, target.first, target.last)) do
      local decl = by_name(decls, n.name)
      if decl and not decl.kind:find("impl", 1, true) then
        push_local(decl)
        seen_names[n.name] = true
      elseif not decl then
        pending_lsp[#pending_lsp + 1] = n
      end
    end

    -- 3. tipos de los campos de lo ya encontrado (mismo archivo, un nivel)
    for _, entry in ipairs(vim.list_slice(entries, 1, #entries)) do
      for word in table.concat(entry.lines, "\n"):gmatch "[%a_][%w_]*" do
        local decl = pascal_case(word) and by_name(decls, word)
        if decl and not decl.kind:find("impl", 1, true) then
          push_local(decl)
        end
      end
    end

    local function finish()
      if #entries == 0 then
        return done(nil)
      end
      local blocks = {}
      for _, e in ipairs(entries) do
        blocks[#blocks + 1] = e.header .. "\n" .. table.concat(e.lines, "\n")
      end
      done(table.concat(blocks, "\n\n"))
    end

    -- 2b. tipos de otros archivos: LSP (definición) + treesitter sobre el archivo de destino
    local clients = vim.lsp.get_clients { bufnr = target.buf, method = "textDocument/definition" }
    local budget = settings.types - #entries
    if #clients == 0 or budget <= 0 or #pending_lsp == 0 then
      return finish()
    end
    pending_lsp = vim.list_slice(pending_lsp, 1, budget + 2)

    local project = vim.fs.root(target.buf, { ".git" }) or vim.fn.getcwd()
    local encoding = clients[1].offset_encoding or "utf-16"
    local remaining, finished = #pending_lsp, false
    local function settle()
      remaining = remaining - 1
      if remaining == 0 and not finished then
        finished = true
        finish()
      end
    end
    vim.defer_fn(function()
      if not finished then
        finished = true
        finish()
      end
    end, settings.hover_timeout_ms)

    for _, n in ipairs(pending_lsp) do
      local line = vim.api.nvim_buf_get_lines(target.buf, n.row, n.row + 1, false)[1] or ""
      local ok, character = pcall(vim.str_utfindex, line, encoding, n.col)
      vim.lsp.buf_request(target.buf, "textDocument/definition", {
        textDocument = vim.lsp.util.make_text_document_params(target.buf),
        position = { line = n.row, character = ok and character or n.col },
      }, function(_, result)
        pcall(function()
          if finished or not result then
            return
          end
          local list = (result.uri or result.targetUri) and { result } or result
          for _, location in ipairs(list) do
            local path, row = location_of(location)
            if
              path
              and path ~= vim.api.nvim_buf_get_name(target.buf)
              and in_project(path, project)
              and vim.fn.getfsize(path) < 400000
            then
              local ft = vim.filetype.match { filename = path }
              local lang = ft and vim.treesitter.language.get_lang(ft)
              local text = table.concat(vim.fn.readfile(path), "\n")
              if lang and text ~= "" then
                local best
                for _, d in ipairs(scopes.type_declarations(text, lang)) do
                  if d.first - 1 <= row and row <= d.last - 1 and not d.kind:find("impl", 1, true) then
                    if not best or (d.last - d.first) < (best.last - best.first) then
                      best = d
                    end
                  end
                end
                if best then
                  local all = vim.split(text, "\n", { plain = true })
                  push(
                    n.name,
                    ("%s (%s:%d)"):format(n.name, vim.fn.fnamemodify(path, ":."), best.first),
                    vim.list_slice(all, best.first, best.last)
                  )
                end
                break
              end
            end
          end
        end)
        settle()
      end)
    end
  end,
}
