-- ── Setup de backends y modelos locales ──────────────────────────────────────
-- Un punto de entrada para dejar el agente listo en una máquina nueva (o cuando cambia algo): detecta CLIs, Ollama (CPU/CUDA),
-- servidores OpenAI-compatibles y modelos; recomienda; y, SOLO si lo pides, arranca Ollama, descarga modelos y fija la
-- selección. Desde nvim: <leader>am → Setup. Desde la terminal: scripts/agent-setup.sh.
--   detect.lua      foto de la máquina (paralela, sin tocar nada)
--   recommend.lua   qué modelo para cada nivel (pura)
--   actions.lua     lo que modifica: arrancar, descargar, recordar, aplicar
--   report.lua      texto (markdown) del estado
local actions = require "agent.setup.actions"
local backends = require "agent.backends"
local detect = require "agent.setup.detect"
local log = require "utils.log"
local recommend = require "agent.setup.recommend"
local report = require "agent.setup.report"
local selection = require "agent.selection"

local M = {}

---@return string?
local function current_label()
  local main = selection.current()
  if not main then
    return nil
  end
  local light = selection.current { name = "", tier = "light" }
  return selection.label(main)
    .. (
      light
        and light.backend .. light.model ~= main.backend .. main.model
        and ("  ·  light " .. selection.label(light))
      or ""
    )
end

--- Foto + recomendación + informe; recuerda de paso los servidores encontrados
---@param cb fun(snap: AgentSnapshot, rec: AgentRecommendation, lines: string[])
function M.scan(cb)
  detect.run(function(snap)
    actions.remember(snap)
    local rec = recommend.pick(snap)
    cb(snap, rec, report.build(snap, rec, current_label()))
  end)
end

---@param snap AgentSnapshot
---@return string url donde debe vivir Ollama (el del backend)
local function ollama_url(snap)
  return snap.ollama_servers[1] and snap.ollama_servers[1].url or backends.get("ollama").host()
end

---@param url string
---@param model string
---@param done fun(ok: boolean)?
function M.pull(url, model, done)
  log.info(("Agent: pulling %s…"):format(model))
  local last = -10
  actions.pull(url, model, function(_, pct)
    if pct and pct >= last + 10 then -- un aviso cada 10 %: sin inundar de notificaciones
      last = pct
      log.info(("Agent: %s %d%%"):format(model, pct))
    end
  end, function(ok, err)
    log.info(ok and ("Agent: %s ready"):format(model) or ("Agent: pull failed — " .. err))
    if done then
      done(ok)
    end
  end)
end

---@param rec AgentRecommendation
local function apply(rec)
  local applied = actions.apply(rec)
  log.info(
    #applied > 0 and ("Agent: " .. table.concat(applied, " · ")) or "Agent: nothing to apply yet (no local models)"
  )
end

--- Menú interactivo (<leader>am → Setup): estado + acciones posibles, todo con el teclado
function M.open()
  log.info "Agent: scanning backends…"
  M.scan(function(snap, rec, lines)
    local items = {}
    local function add(label, run)
      items[#items + 1] = { label = label, run = run }
    end
    if rec.main or rec.light then
      add(
        ("Use detected models  (%s)"):format(table.concat(
          vim.tbl_filter(function(x)
            return x
          end, {
            rec.main and "main " .. rec.main.model or nil,
            rec.light and "light " .. rec.light.model or nil,
          }),
          " · "
        )),
        function()
          apply(rec)
        end
      )
    end
    local ollama_cli = vim.tbl_filter(function(c)
      return c.name == "ollama" and c.path
    end, snap.clis)[1]
    if ollama_cli and #snap.ollama_servers == 0 then
      add("Start Ollama server  (ollama serve)", function()
        actions.start_ollama(ollama_url(snap), function(ok, err)
          log.info(ok and "Agent: Ollama is running — open Setup again to pick models" or ("Agent: " .. err))
        end)
      end)
    end
    if #snap.ollama_servers > 0 then
      for _, p in ipairs(rec.pulls) do
        add(("Download %s  — %s"):format(p.model, p.why), function()
          M.pull(ollama_url(snap), p.model)
        end)
      end
    end
    add("Show full status report", function()
      require("agent.ui.panel").open(lines, "Agent setup")
    end)
    local ready = report.ready(snap)
    require("agent.ui.select").pick(items, {
      title = ready and "Agent · setup" or "Agent · setup (no backend ready yet: see the report)",
    }, function(choice)
      choice.run()
    end)
  end)
end

-- ── Terminal: scripts/agent-setup.sh ─────────────────────────────────────────

--- Ejecuta una orden del script y termina nvim con el código de salida. Banderas explícitas = consentimiento para
--- arrancar / descargar (nunca se hace nada que no se haya pedido).
---   (sin banderas) / --check   informe; exit 0 si hay al menos un backend listo, 1 si no
---   --start                    arranca `ollama serve` si no responde
---   --pull MODELO              descarga un modelo en el servidor de Ollama
---   --use BACKEND/MODELO[:light]  fija backend y modelo (main, o light con el sufijo `@light`)
---   --auto                     aplica la recomendación (modelos ya instalados)
---   --json                     la foto en JSON (para otras herramientas)
---@param args string[]
function M.cli(args)
  local function say(s)
    io.stdout:write(s .. "\n")
  end
  local function quit(code)
    vim.schedule(function()
      vim.cmd(("silent! %dcquit"):format(code))
    end)
  end
  local want = { json = false, start = false, auto = false, pulls = {}, uses = {} }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--json" then
      want.json = true
    elseif a == "--start" then
      want.start = true
    elseif a == "--auto" then
      want.auto = true
    elseif a == "--pull" and args[i + 1] then
      want.pulls[#want.pulls + 1] = args[i + 1]
      i = i + 1
    elseif a == "--use" and args[i + 1] then
      want.uses[#want.uses + 1] = args[i + 1]
      i = i + 1
    elseif a ~= "--check" then
      say("agent-setup: unknown argument " .. a)
      return quit(2)
    end
    i = i + 1
  end

  -- 1) --use no necesita red: se valida y se aplica
  for _, spec in ipairs(want.uses) do
    local tier = "main"
    local base = spec:gsub("@light$", function()
      tier = "light"
      return ""
    end)
    local backend, model = actions.parse_spec(base)
    if not backend then
      say(
        ("agent-setup: bad --use %q (expected backend/model, backend one of: %s)"):format(
          spec,
          table.concat(backends.names(), ", ")
        )
      )
      return quit(2)
    end
    selection.set(backend, model, tier)
    say(("set %s → %s/%s"):format(tier, backend, model))
  end

  local function after_start()
    local function after_pulls(snap)
      if want.auto then
        for _, line in ipairs(actions.apply(recommend.pick(snap))) do
          say("set " .. line)
        end
      end
      local rec = recommend.pick(snap)
      if want.json then
        say(vim.json.encode { snapshot = snap, recommendation = rec, ready = report.ready(snap) })
      else
        say(table.concat(report.build(snap, rec, current_label()), "\n"))
      end
      quit(report.ready(snap) and 0 or 1)
    end

    local function scan_and_continue()
      detect.run(function(snap)
        actions.remember(snap)
        after_pulls(snap)
      end)
    end

    if #want.pulls == 0 then
      return scan_and_continue()
    end
    detect.run(function(snap)
      local url = ollama_url(snap)
      local idx = 0
      local function next_pull()
        idx = idx + 1
        local model = want.pulls[idx]
        if not model then
          return scan_and_continue()
        end
        say(("pulling %s from %s"):format(model, url))
        actions.pull(url, model, function(status, pct)
          if pct and pct % 25 == 0 then
            say(("  %s %d%%"):format(status, pct))
          end
        end, function(ok, err)
          say(ok and ("  %s ready"):format(model) or ("  failed: " .. err))
          next_pull()
        end)
      end
      next_pull()
    end)
  end

  if want.start then
    return actions.start_ollama(backends.get("ollama").host(), function(ok, err)
      say(ok and "ollama server: running" or ("ollama server: " .. err))
      after_start()
    end)
  end
  after_start()
end

return M
