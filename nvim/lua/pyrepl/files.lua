-- ── Python REPL: el folder de trabajo ─────────────────────────────────────────
-- Un directorio en stdpath("state")/python-repl con un .py por sesión y un
-- sessions.json. Cada sesión tiene su propio "cuaderno" de celdas y su salida.
local M = {}

local function config()
  local ok, settings = pcall(require, "core.settings")
  if ok and settings.python and settings.python.repl then
    return settings.python.repl
  end
  return {}
end

---@return string
function M.dir()
  local folder = config().folder
  local path = folder and vim.fn.expand(folder) or (vim.fn.stdpath "state" .. "/python-repl")
  vim.fn.mkdir(path, "p")
  return path
end

---@param name string
---@return string
function M.safe(name)
  return (tostring(name):gsub("[^%w_%-]", "_"))
end

---@param name string
---@return string
function M.file(name)
  return M.dir() .. "/" .. M.safe(name) .. ".py"
end

---@param name string
---@return string
function M.output_file(name)
  return M.dir() .. "/" .. M.safe(name) .. ".out.txt"
end

---@return string
function M.state_path()
  return M.dir() .. "/sessions.json"
end

---@return table[]
function M.read()
  local f = io.open(M.state_path(), "r")
  if not f then
    return {}
  end
  local text = f:read "*a"
  f:close()
  local ok, data = pcall(vim.json.decode, text)
  return ok and type(data) == "table" and data or {}
end

---@param sessions table[]
function M.write(sessions)
  local f = assert(io.open(M.state_path(), "w"))
  f:write(vim.json.encode(sessions))
  f:close()
end

--- Crea el archivo de celdas si no existe y registra/actualiza la sesión.
---@param name string
---@param cwd string?
---@return string path
function M.ensure(name, cwd)
  local path = M.file(name)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({
      '# Python REPL workspace · ' .. name,
      "# Escribe celdas y envíalas con <leader>pCc",
      "# %%",
      "",
    }, path)
  end
  local sessions = M.read()
  local found
  for _, session in ipairs(sessions) do
    if session.name == name then
      found = session
      break
    end
  end
  if not found then
    found = { name = name }
    table.insert(sessions, found)
  end
  found.cwd = cwd or found.cwd
  found.updated = os.time()
  M.write(sessions)
  return path
end

---@return string[]
function M.names()
  local names = {}
  for _, session in ipairs(M.read()) do
    names[#names + 1] = session.name
  end
  return names
end

--- La sesión usada más recientemente (la que el workspace retoma al abrir).
---@return string?
function M.last()
  local best, best_time
  for _, session in ipairs(M.read()) do
    local at = session.updated or 0
    if not best_time or at >= best_time then
      best, best_time = session.name, at
    end
  end
  return best
end

---@param name string
---@param text string
function M.save_output(name, text)
  local f = assert(io.open(M.output_file(name), "w"))
  f:write(text)
  f:close()
end

--- Picker de sesiones (Telescope, el mismo widget que los presets de tareas).
---@param cb fun(name:string)
function M.pick(cb)
  local items = { { label = "New session…", value = "__new__", desc = "create a named workspace" } }
  for _, session in ipairs(M.read()) do
    items[#items + 1] = { label = session.name, value = session.name, desc = session.cwd or "" }
  end
  require("tasks.picker").choose(items, {
    title = "Python REPL",
    hint = "sessions",
    width = 16,
  }, cb)
end

return M
