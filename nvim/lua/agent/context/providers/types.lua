-- Definitions of the TYPES the target uses: it is what stops the model from guessing the fields of
-- `Note` or the methods of `Repo`. Language-independent (treesitter `textobjects` queries):
--   1. type names in the target: `*type_identifier*` nodes and, where there are none (Python, JS, Lua), the
--      PascalCase identifiers;
--   2. if the type is in the SAME file, it is read instantly with treesitter; otherwise the
--      LSP is asked for its definition and it is extracted from the destination file (project only, not dependencies);
--   3. the types of the fields of what was found (`Tags []Tag`) are followed one level, within the file;
--   4. if the target is a method (Python/TS/Java...), the class that contains it, without the method itself.
-- Cap on types and on lines per type: it is context, not the repository.
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

-- full-line comments: `//` `///` `/* … */` `*` (C family, Go, Dart, Rust, JS/TS, Java, Kotlin, Swift), `--` (Lua, SQL) and `#`
-- where it is a comment (Python, Ruby, shell; never Rust's `#[derive]` or C's `#include`)
local HASH_COMMENTS = { python = true, ruby = true, sh = true, bash = true, zsh = true, yaml = true, toml = true }

local function is_comment(line, lang)
  local s = line:match "^%s*(.-)%s*$"
  return s:match "^//" ~= nil
    or s:match "^/%*" ~= nil
    or s:match "^%*" ~= nil
    or s:match "^%-%-" ~= nil
    or (HASH_COMMENTS[lang] == true and s:match "^#" ~= nil)
end

local ENUM_RUN = 4 -- this many bare values in a row (`go,` `bash,` …) are joined into one line
local JOIN_WIDTH = 100
local ENUM_VALUES = 24 -- values shown from one run; the rest is counted (the model needs their kind, not all of them)

--- A type definition as the model needs it: what it declares, not how it is documented. Full-line comments (doc
--- comments of fields and values) and blank lines go (`settings.agent.context.type_comments = true` keeps comments),
--- and long runs of bare enum values are joined (at most 24, the rest counted): a long enum with a comment per value
--- shrinks to a few lines.
--- Comments at the end of a code line stay.
---@param lines string[]
---@param lang string
---@param keep_comments boolean?
---@return string[]
local function compact(lines, lang, keep_comments)
  local kept = {}
  for _, line in ipairs(lines) do
    if line:match "%S" and (keep_comments or not is_comment(line, lang)) then
      kept[#kept + 1] = line
    end
  end
  local out, i = {}, 1
  while i <= #kept do
    local j = i
    while j <= #kept and kept[j]:match "^%s*[%a_][%w_]*%s*,?%s*$" do
      j = j + 1
    end
    if j - i >= ENUM_RUN then
      local indent = kept[i]:match "^%s*"
      local row = indent
      local last = math.min(j - 1, i + ENUM_VALUES - 1)
      for k = i, last do
        local value = kept[k]:match "^%s*([%a_][%w_]*)"
        local piece = value .. ((k < j - 1 or kept[k]:find(",", 1, true)) and ", " or "")
        if k == last and last < j - 1 then
          piece = piece .. ("… (%d more)"):format(j - 1 - last)
        end
        if #row + #piece > JOIN_WIDTH and row ~= indent then
          out[#out + 1] = row:gsub("%s+$", "")
          row = indent
        end
        row = row .. piece
      end
      out[#out + 1] = row:gsub("%s+$", "")
      i = j
    else
      out[#out + 1] = kept[i]
      i = i + 1
    end
  end
  return out
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

--- Best declaration for a name: a type definition before an `impl`
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
  if require("utils.generated").is_generated(path) then
    return false -- `x.freezed.dart` defines the same class again, ~5x longer: the source is what the model needs
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

local M = {}

M.compact = compact

--- Identifiers the LSP diagnostics point at inside the target (max. 4): the type of each one is requested from there.
--- Agent findings cover the whole line (nothing concrete to resolve): they do not count.
---@param target AgentTarget
---@return { name: string, row: integer, col: integer }[]
function M.diagnostic_identifiers(target)
  local agent_ns = require("agent.output.findings").namespace()
  local out, seen = {}, {}
  for _, d in ipairs(vim.diagnostic.get(target.buf)) do
    if d.namespace ~= agent_ns and d.lnum + 1 >= target.first and d.lnum + 1 <= target.last then
      for _, id in ipairs(scopes.identifiers_in(target.buf, d.lnum, d.col, d.end_lnum or d.lnum, d.end_col or d.col)) do
        local key = id.row .. ":" .. id.col
        if not seen[key] and #out < 4 then
          seen[key] = true
          out[#out + 1] = id
        end
      end
    end
  end
  return out
end

return vim.tbl_extend("error", M, {
  cap = 3500,
  stability = 2,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  ---@param ctx { action: table }?
  collect = function(target, done, ctx)
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
    -- fix: the objects a diagnostic points at (the type of a variable that is not named in the code)
    -- are resolved with `typeDefinition` and may exceed the type cap
    local typedefs = (ctx and ctx.action and ctx.action.fixes) and M.diagnostic_identifiers(target) or {}
    local extra = math.min(#typedefs, 2)
    local function overlaps_target(first, last)
      return first <= target.last and target.first <= last
    end

    ---@param name string
    ---@param header string
    ---@param lines string[]
    local function push(name, header, lines)
      if #entries < settings.types + extra and not included[name] then
        included[name] = true
        entries[#entries + 1] = {
          name = name,
          header = header,
          lines = clip(compact(lines, target.lang, settings.type_comments), settings.type_lines),
        }
      end
    end

    local function push_local(decl)
      if decl.name and not overlaps_target(decl.first, decl.last) then
        local lines = vim.api.nvim_buf_get_lines(target.buf, decl.first - 1, decl.last, false)
        -- the values of an enum-like type (Pending, Confirmed...) live in a separate `const (...)`
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

    -- 4. the class containing the target (methods in Python/TS/Java/Rust)
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
        push_local(struct) -- Rust: `impl Note` → the definition of `struct Note`
      elseif enclosing_decl then
        -- the whole class minus the method itself (which already goes as the target)
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

    -- 1-2. types used by the target
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

    -- 3. types of the fields of what was already found (same file, one level)
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

    -- 2b. types from other files: LSP (definition) + treesitter on the destination file.
    -- The `typedefs` requests (typeDefinition) go first: they are what the diagnostic points at.
    local requests = {}
    local method_ok = function(method)
      return #vim.lsp.get_clients { bufnr = target.buf, method = method } > 0
    end
    if method_ok "textDocument/typeDefinition" then
      for _, n in ipairs(typedefs) do
        requests[#requests + 1] = { name = n.name, row = n.row, col = n.col, method = "textDocument/typeDefinition" }
      end
    end
    if method_ok "textDocument/definition" then
      for _, n in ipairs(vim.list_slice(pending_lsp, 1, math.max(settings.types - #entries, 0) + 2)) do
        requests[#requests + 1] = { name = n.name, row = n.row, col = n.col, method = "textDocument/definition" }
      end
    end
    if #requests == 0 or #entries >= settings.types + extra then
      return finish()
    end

    local clients = vim.lsp.get_clients { bufnr = target.buf }
    local project = vim.fs.root(target.buf, { ".git" }) or vim.fn.getcwd()
    local encoding = clients[1].offset_encoding or "utf-16"
    local self_path = vim.api.nvim_buf_get_name(target.buf)
    local remaining, finished = #requests, false
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

    for _, n in ipairs(requests) do
      local line = vim.api.nvim_buf_get_lines(target.buf, n.row, n.row + 1, false)[1] or ""
      local ok, character = pcall(vim.str_utfindex, line, encoding, n.col)
      vim.lsp.buf_request(target.buf, n.method, {
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
            if path == self_path and n.method == "textDocument/typeDefinition" then
              -- the variable is of a type from THIS file: it is already read (definition does not ask for it: the code names it)
              local best
              for _, d in ipairs(decls) do
                if d.first - 1 <= row and row <= d.last - 1 and d.name and not d.kind:find("impl", 1, true) then
                  if not best or (d.last - d.first) < (best.last - best.first) then
                    best = d
                  end
                end
              end
              if best then
                push_local(best)
              end
              break
            elseif path and path ~= self_path and in_project(path, project) and vim.fn.getfsize(path) < 400000 then
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
                  local name = best.name or n.name
                  push(
                    name,
                    ("%s (%s:%d)"):format(name, vim.fn.fnamemodify(path, ":."), best.first),
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
})
