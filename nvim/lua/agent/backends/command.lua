-- ── Backend declarativo: cualquier agente por línea de comandos ──────────────────────────────────────────────────
-- Una entrada en `settings.agent.custom` basta para integrar Hermes Agent, Gemini CLI, Codex, Aider u otro CLI que
-- reciba un prompt y escriba la respuesta:
--
--   custom = {
--     hermes = {
--       label = "Hermes Agent",
--       cmd = { "hermes", "chat", "-q", "{prompt}" },  -- {prompt} {system} {model} se sustituyen en cada argumento
--       system_in_prompt = true,                       -- el CLI no tiene bandera de system: va dentro del mensaje
--       stdin = false,                                 -- true: el mensaje va por stdin en vez de por {prompt}
--       model_flag = { "-m", "{model}" },              -- opcional: se añade si hay modelo elegido
--       models = { "default" },                        -- o models_cmd = { "hermes", "models" } (una id por línea)
--       json = nil,                                    -- "a.b.c": la salida son eventos JSON por línea; el texto está en esa ruta
--       env = {},
--     },
--   }
--
-- Corre en el directorio neutro (agent/sandbox), sin herramientas del propio proyecto. REVISA las banderas de tu versión:
-- la entrada es tuya, el agente no las adivina.
local sandbox = require "agent.sandbox"
local text = require "agent.text"

local M = {}

---@param s string
---@param vars table<string, string>
---@return string
local function expand(s, vars)
  return (s:gsub("{(%w+)}", function(k)
    return vars[k] or ("{" .. k .. "}")
  end))
end

--- Valor en una ruta "a.b.c" de una tabla
---@param tbl table
---@param path string
---@return any
local function dig(tbl, path)
  local v = tbl
  for key in path:gmatch "[^%.]+" do
    if type(v) ~= "table" then
      return nil
    end
    v = v[tonumber(key) or key]
  end
  return v
end

---@param name string
---@param spec table
---@return table backend
function M.from_spec(name, spec)
  local B = { name = name, label = spec.label or name, default_model = spec.model, requires_model = false }

  function B.available()
    return type(spec.cmd) == "table" and vim.fn.executable(spec.cmd[1]) == 1
  end

  ---@param cb fun(models: table[])
  function B.models(cb)
    if spec.models then
      return cb(vim.tbl_map(function(id)
        return { id = id }
      end, spec.models))
    end
    if spec.models_cmd then
      return vim.system(spec.models_cmd, { text = true }, function(out)
        vim.schedule(function()
          local list = {}
          for line in (out.stdout or ""):gmatch "[^\r\n]+" do
            list[#list + 1] = { id = vim.trim(line) }
          end
          cb(list)
        end)
      end)
    end
    cb {}
  end

  function B.build(req)
    local message = req.prompt
    if spec.system_in_prompt ~= false then
      message = ("<instructions>\n%s\n</instructions>\n\n%s"):format(req.system, req.prompt)
    end
    local vars = { prompt = message, system = req.system, model = req.model or "" }
    local cmd = vim.tbl_map(function(arg)
      return expand(arg, vars)
    end, spec.cmd)
    if spec.model_flag and req.model then
      for _, arg in ipairs(spec.model_flag) do
        cmd[#cmd + 1] = expand(arg, vars)
      end
    end
    return { cmd = cmd, stdin = spec.stdin and message or nil, env = spec.env, cwd = sandbox.dir() }
  end

  function B.parser()
    local chunks, pending = {}, ""
    local function line_text(line)
      if not spec.json then
        return line .. "\n"
      end
      local ok, ev = pcall(vim.json.decode, line)
      local v = ok and type(ev) == "table" and dig(ev, spec.json) or nil
      return type(v) == "string" and v or nil
    end
    return {
      feed = function(chunk)
        pending = pending .. chunk
        local out = {}
        while true do
          local nl = pending:find("\n", 1, true)
          if not nl then
            break
          end
          local piece = line_text(pending:sub(1, nl - 1))
          pending = pending:sub(nl + 1)
          if piece then
            chunks[#chunks + 1] = piece
            out[#out + 1] = piece
          end
        end
        return #out > 0 and table.concat(out) or nil
      end,
      finish = function(code, stderr)
        if pending ~= "" then
          local piece = line_text(pending)
          if piece then
            chunks[#chunks + 1] = piece
          end
        end
        local body = text.trim(table.concat(chunks))
        if body == "" then
          local msg = text.trim(stderr)
          return {
            ok = false,
            err = msg ~= "" and msg
              or (code ~= 0 and ("%s exited with code %d"):format(name, code) or "empty response"),
          }
        end
        return { ok = true, text = body }
      end,
    }
  end

  return B
end

return M
