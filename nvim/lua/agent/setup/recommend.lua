-- ── Recomendación (pura): qué modelo local usar para cada nivel ──────────────
-- Sin I/O: recibe la foto de `detect` y devuelve una propuesta. Reglas simples y a la vista:
--   · Con los modelos que YA tienes: el de código más grande para el principal, el más pequeño para el ligero.
--   · Sin ninguno: se SUGIERE bajar un par según tu VRAM (o RAM, si no hay GPU); nunca se descarga sin pedírtelo.
--   · Claude/OpenCode siguen siendo el principal si están: los modelos locales cubren el nivel ligero (docs, explain),
--     donde un modelo pequeño basta y el coste es 0. Sin ningún CLI de nube, el local pasa a ser también el principal.
local M = {}

--- Escalones por memoria disponible (GB): modelos de código de la familia qwen2.5-coder (muy buenos para su tamaño)
M.TIERS = {
  { min = 22, main = "qwen2.5-coder:32b", light = "qwen2.5-coder:7b" },
  { min = 10, main = "qwen2.5-coder:14b", light = "qwen2.5-coder:3b" },
  { min = 6, main = "qwen2.5-coder:7b", light = "qwen2.5-coder:1.5b" },
  { min = 0, main = "qwen2.5-coder:3b", light = "qwen2.5-coder:1.5b" },
}

--- Memoria útil para modelos: VRAM si hay GPU; en CPU, la mitad de la RAM y con tope (más grande sería inusablemente lento)
---@param snap AgentSnapshot
---@return number
function M.budget_gb(snap)
  if snap.gpu then
    return snap.gpu.vram_gb
  end
  return math.min((snap.ram_gb or 8) / 2, 8)
end

---@param snap AgentSnapshot
---@return table tier
function M.tier(snap)
  local gb = M.budget_gb(snap)
  for _, t in ipairs(M.TIERS) do
    if gb >= t.min then
      return t
    end
  end
  return M.TIERS[#M.TIERS]
end

--- Tamaño en miles de millones de parámetros a partir del nombre ("qwen2.5-coder:7b" → 7) o de `params` ("7.6B")
---@param m { name: string, params: string? }
---@return number
local function billions(m)
  local n = (m.params or ""):match "([%d%.]+)%s*[Bb]" or m.name:match ":([%d%.]+)[bB]"
  return tonumber(n) or 0
end

local function is_coder(name)
  return name:find("coder", 1, true) ~= nil
    or name:find("codellama", 1, true) ~= nil
    or name:find("starcoder", 1, true) ~= nil
end

---@param snap AgentSnapshot
---@return { server: string, name: string, b: number, coder: boolean }[]
local function installed(snap)
  local list = {}
  for _, s in ipairs(snap.ollama_servers) do
    for _, m in ipairs(s.models) do
      if not m.name:find("embed", 1, true) then
        list[#list + 1] = { server = s.url, name = m.name, b = billions(m), coder = is_coder(m.name) }
      end
    end
  end
  -- modelos de código primero; dentro, de mayor a menor
  table.sort(list, function(a, b)
    if a.coder ~= b.coder then
      return a.coder
    end
    if a.b ~= b.b then
      return a.b > b.b
    end
    return a.name < b.name
  end)
  return list
end

---@class AgentRecommendation
---@field main { backend: string, model: string }?   solo si no hay CLI de nube
---@field light { backend: string, model: string }?
---@field pulls { model: string, why: string }[]
---@field notes string[]

---@param snap AgentSnapshot
---@return AgentRecommendation
function M.pick(snap)
  local rec = { pulls = {}, notes = {} }
  local cloud = false
  for _, cli in ipairs(snap.clis) do
    if (cli.name == "claude" or cli.name == "opencode") and cli.path then
      cloud = true
    end
  end

  local have = installed(snap)
  if #have > 0 then
    -- el ligero: el modelo de código más pequeño que no sea el mismo que el principal (si solo hay uno, ese)
    local main = have[1]
    local light = main
    for i = #have, 1, -1 do
      if have[i].coder == main.coder and have[i].b >= 1 then
        light = have[i]
        break
      end
    end
    rec.light = { backend = "ollama", model = light.name }
    if not cloud then
      rec.main = { backend = "ollama", model = main.name }
    end
    if not main.coder then
      rec.notes[#rec.notes + 1] = "no code-specialised model installed: results can be weaker (try qwen2.5-coder)"
    end
    return rec
  end

  local tier = M.tier(snap)
  local mem = snap.gpu and ("%s · %.0f GB VRAM"):format(snap.gpu.name, snap.gpu.vram_gb)
    or ("CPU only · ~%.0f GB usable RAM"):format(M.budget_gb(snap))
  rec.pulls[#rec.pulls + 1] = { model = tier.light, why = "light tier (docs, explain) — fits " .. mem }
  if not cloud then
    rec.pulls[#rec.pulls + 1] = { model = tier.main, why = "main tier (implement, fix, review) — fits " .. mem }
  end
  if not snap.gpu then
    rec.notes[#rec.notes + 1] = "no NVIDIA GPU detected: Ollama will run on CPU (slower; fine for the light tier)"
  end
  return rec
end

return M
