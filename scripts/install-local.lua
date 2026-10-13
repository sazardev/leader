-- Escribe los ajustes por máquina (nvim/lua/local.lua, ignorado por git) que piden las opciones del instalador. Lo usan
-- install.sh e install.ps1 (una sola implementación, sin cargar la config ni los plugins):
--   nvim -u NONE --headless -l scripts/install-local.lua
-- Entrada (variables de entorno, todas opcionales):
--   NVIM_INSTALL_LANGS   "go,typescript"  deja solo esos lenguajes (+ lua); el resto va a `languages.disabled`
--   NVIM_INSTALL_THEME   "catppuccin"     `theme.name`
--   NVIM_INSTALL_LIGHT   "1" | "0"        `light.force` (modo ligero forzado / apagado)
--   NVIM_INSTALL_LOCAL   ruta             dónde escribir (por defecto nvim/lua/local.lua; sirve a las pruebas)
--   NVIM_INSTALL_DRY     "1"              enseña lo que escribiría sin escribir
-- Salida: una línea por aviso, con prefijo `OK `, `WARN ` o `ERR ` (el instalador las pinta); sale con 2 si hay un ERR.
-- Si local.lua ya existe NO se toca: se dice qué añadir (es tuyo, puede tener otros ajustes).
local M = {}

local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

--- Nombres de lenguajes del registro (sin cargarlo: se lee su lista `NAMES`)
---@param root string
---@return string[]
function M.language_names(root)
  local ok, lines = pcall(vim.fn.readfile, root .. "/nvim/lua/languages/init.lua")
  local names, inside = {}, false
  for _, line in ipairs(ok and lines or {}) do
    if line:match "^local NAMES = {" then
      inside = true
    elseif inside and line:match "^}" then
      break
    elseif inside then
      local name = line:match '"([%w_]+)"'
      if name then
        names[#names + 1] = name
      end
    end
  end
  return names
end

---@param value any
---@return string
local function lua_value(value)
  if type(value) == "table" then
    if vim.islist(value) then
      return "{ " .. table.concat(vim.tbl_map(lua_value, value), ", ") .. " }"
    end
    local keys = vim.tbl_keys(value)
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = ("%s = %s"):format(k, lua_value(value[k]))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  return type(value) == "string" and ("%q"):format(value) or tostring(value)
end

---@param env { langs: string?, theme: string?, light: string? }
---@param names string[]
---@return table? settings, string? err
function M.plan(env, names)
  local settings = {}
  if env.langs then
    local keep = { lua = true }
    for lang in env.langs:gmatch "[^,%s]+" do
      if not vim.tbl_contains(names, lang) then
        return nil, ("lenguaje desconocido: %s (disponibles: %s)"):format(lang, table.concat(names, " "))
      end
      keep[lang] = true
    end
    settings.languages = {
      disabled = vim.tbl_filter(function(n)
        return not keep[n]
      end, names),
    }
  end
  if env.theme then
    settings.theme = { name = env.theme }
  end
  if env.light == "1" or env.light == "0" then
    settings.light = { force = env.light == "1" }
  end
  return settings
end

---@param settings table
---@return string
function M.render(settings)
  return "return " .. lua_value(settings)
end

---@param value string?
---@return string?
local function nonempty(value)
  return value and value ~= "" and value or nil
end

function M.main()
  local env = {
    langs = nonempty(os.getenv "NVIM_INSTALL_LANGS"),
    theme = nonempty(os.getenv "NVIM_INSTALL_THEME"),
    light = nonempty(os.getenv "NVIM_INSTALL_LIGHT"),
  }
  local path = nonempty(os.getenv "NVIM_INSTALL_LOCAL") or (ROOT .. "/nvim/lua/local.lua")
  local settings, err = M.plan(env, M.language_names(ROOT))
  if not settings then
    io.stdout:write("ERR ", err, "\n")
    os.exit(2)
  end
  if next(settings) == nil then
    return
  end
  local body = M.render(settings)
  local summary = body:gsub("^return ", "")
  if vim.uv.fs_stat(path) then
    io.stdout:write("WARN lua/local.lua ya existe: añade dentro de su tabla → ", summary:sub(3, -3), "\n")
  elseif os.getenv "NVIM_INSTALL_DRY" == "1" then
    io.stdout:write("OK [dry-run] escribiría lua/local.lua: ", body, "\n")
  else
    vim.fn.writefile({ "-- Generado por el instalador (ajustes por máquina, ignorado por git)", body }, path)
    io.stdout:write("OK lua/local.lua: ", summary, "\n")
  end
end

if not vim.g.install_local_test then
  M.main()
  vim.cmd "qa!"
end

return M
