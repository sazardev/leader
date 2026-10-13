-- ── Convenciones de pruebas por lenguaje (sin LLM, 0 tokens) ─────────────────
-- Dónde viven las pruebas de un archivo, con qué framework, y cómo se corre una. Es lo que permite pedirle al
-- modelo SOLO el código nuevo y ponerlo en el sitio correcto: el pipeline recibe el final del archivo de pruebas
-- como objetivo (agent/tests/actions/*.retarget) en vez de la función.
local M = {}

---@class AgentTestInfo
---@field path string     ruta absoluta del archivo de pruebas
---@field exists boolean
---@field inline boolean  las pruebas viven en el mismo archivo (Rust)
---@field framework string
---@field style string    una línea de estilo para el prompt

local ROOT_MARKERS = { ".git", "go.mod", "package.json", "pyproject.toml", "Cargo.toml", "pubspec.yaml", "pom.xml" }

---@param path string
---@return string
function M.root(path)
  return vim.fs.root(path, ROOT_MARKERS) or vim.fs.dirname(path)
end

---@param path string
---@return string?
local function slurp(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or nil
end

---@param root string
---@param file string
---@param needle string
---@return boolean
local function project_mentions(root, file, needle)
  local text = slurp(root .. "/" .. file)
  return text ~= nil and text:find(needle, 1, true) ~= nil
end

--- ¿Es un archivo de pruebas?
---@param path string
---@return boolean
function M.is_test_file(path)
  local name = vim.fs.basename(path)
  return name:match "_test%.%w+$" ~= nil
    or name:match "%.test%.%w+$" ~= nil
    or name:match "%.spec%.%w+$" ~= nil
    or name:match "^test_.+%.py$" ~= nil
    or name:match "_spec%.lua$" ~= nil
    or name:match "Tests?%.%w+$" ~= nil and (path:find("/src/test/", 1, true) ~= nil or path:find("/test/", 1, true) ~= nil)
    or path:find("/tests/", 1, true) ~= nil and not name:match "^__init__"
end

local TS = { typescript = "ts", typescriptreact = "tsx", javascript = "js", javascriptreact = "jsx" }

--- Dónde van las pruebas de `path`. nil + motivo si el lenguaje no tiene convención conocida
---@param path string absoluta
---@param lang string filetype
---@return AgentTestInfo?, string? why
function M.locate(path, lang)
  local dir, base = vim.fs.dirname(path), vim.fs.basename(path)
  local stem = base:gsub("%.[^.]+$", "")
  local root = M.root(path)
  ---@type AgentTestInfo
  local info = { exists = false, inline = false, framework = "", style = "", path = "" }

  if lang == "go" then
    info.path = ("%s/%s_test.go"):format(dir, stem)
    info.framework = project_mentions(root, "go.mod", "testify") and "Go testing + testify (assert/require)"
      or "Go testing"
    info.style = "same package as the code; table-driven tests with t.Run subtests; t.Helper() in helpers"
  elseif TS[lang] then
    local ext = TS[lang]
    local suffix = vim.fn.glob(dir .. "/*.spec.*") ~= "" and "spec" or "test"
    info.path = ("%s/%s.%s.%s"):format(dir, stem, suffix, ext)
    for _, s in ipairs { "spec", "test" } do
      local candidate = ("%s/%s.%s.%s"):format(dir, stem, s, ext)
      if vim.uv.fs_stat(candidate) then
        info.path = candidate
      end
    end
    local pkg = slurp(root .. "/package.json") or ""
    info.framework = pkg:find("vitest", 1, true) and "vitest (import { describe, it, expect, vi } from 'vitest')"
      or pkg:find("jest", 1, true) and "jest (describe/it/expect, jest.fn)"
      or pkg:find("mocha", 1, true) and "mocha + chai"
      or "node:test / vitest-style describe/it/expect"
    info.style = "describe per function, it per behaviour; typed; no any"
  elseif lang == "python" then
    -- una carpeta tests/ junto al código, o la del proyecto; si no hay, junto al código
    local tests_dir = vim.uv.fs_stat(dir .. "/tests") and (dir .. "/tests")
      or vim.uv.fs_stat(root .. "/tests") and (root .. "/tests")
      or dir
    info.path = ("%s/test_%s.py"):format(tests_dir, stem)
    info.framework = "pytest"
    info.style = "plain functions named test_<behaviour>; pytest.mark.parametrize for tables; fixtures over setup code"
  elseif lang == "lua" then
    info.path = ("%s/%s_spec.lua"):format(dir, stem)
    info.framework = "busted-style (describe/it/assert)"
    info.style = "describe per function, it per behaviour"
  elseif lang == "rust" then
    info.path, info.inline = path, true
    info.framework = "cargo test (#[test])"
    info.style = "append a `#[cfg(test)] mod <name>_tests { use super::*; ... }` block"
  elseif lang == "dart" then
    local rel = path:gsub("/lib/", "/test/", 1)
    info.path = rel:gsub("%.dart$", "_test.dart")
    local pub = slurp(root .. "/pubspec.yaml") or ""
    info.framework = pub:find("flutter", 1, true) and "flutter_test (testWidgets/test)" or "package:test"
    info.style = "group per function, test per behaviour"
  elseif lang == "java" or lang == "kotlin" then
    local ext = lang == "java" and "java" or "kt"
    local rel = path:gsub("/src/main/", "/src/test/", 1)
    info.path = rel:gsub("%." .. ext .. "$", "Test." .. ext)
    info.framework = "JUnit 5"
    info.style = "one @Test per behaviour; @ParameterizedTest for tables"
  else
    return nil, ("no test convention for filetype `%s` (Go, TS/JS, Python, Lua, Rust, Dart, Java, Kotlin)"):format(lang)
  end
  info.exists = vim.uv.fs_stat(info.path) ~= nil
  return info
end

---@class AgentTestRun
---@field cmd string[]
---@field cwd string
---@field label string

--- Cómo correr UNA prueba (para arreglarla con su salida real). nil + motivo si no se sabe
---@param path string
---@param lang string
---@param name string? nombre de la función de prueba
---@return AgentTestRun?, string? why
function M.command(path, lang, name)
  local root = M.root(path)
  local rel = vim.fs.relpath and vim.fs.relpath(root, path) or path:sub(#root + 2)
  if lang == "go" then
    local cmd = { "go", "test", "./" .. (vim.fs.dirname(rel) == "." and "" or vim.fs.dirname(rel)), "-count=1" }
    if name then
      vim.list_extend(cmd, { "-run", "^" .. name .. "$" })
    end
    return { cmd = cmd, cwd = root, label = table.concat(cmd, " ") }
  elseif TS[lang] then
    local pkg = slurp(root .. "/package.json") or ""
    local tool = pkg:find("vitest", 1, true) and { "npx", "--no-install", "vitest", "run", rel }
      or pkg:find("jest", 1, true) and { "npx", "--no-install", "jest", rel }
    if not tool then
      return nil, "no vitest or jest in package.json"
    end
    if name then
      vim.list_extend(tool, { "-t", name })
    end
    return { cmd = tool, cwd = root, label = table.concat(tool, " ") }
  elseif lang == "python" then
    local cmd = { "python3", "-m", "pytest", "-x", "-q", "--no-header", rel }
    if name then
      vim.list_extend(cmd, { "-k", name })
    end
    return { cmd = cmd, cwd = root, label = table.concat(cmd, " ") }
  elseif lang == "rust" then
    local cmd = { "cargo", "test", "--quiet" }
    if name then
      cmd[#cmd + 1] = name
    end
    return { cmd = cmd, cwd = root, label = table.concat(cmd, " ") }
  end
  return nil, ("don't know how to run `%s` tests here (Go, TS/JS, Python and Rust are supported)"):format(lang)
end

return M
