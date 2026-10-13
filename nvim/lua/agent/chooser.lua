-- ── Elegir backend, modelo y esfuerzo ────────────────────────────────────────
-- Una sola lista fuzzy con TODOS los modelos de todos los backends instalados
-- ("Claude haiku", "OpenCode opencode-go/qwen3.8-flash"...): elegir uno cambia también
-- de backend. Se recuerda entre sesiones (agent/state).
local backends = require "agent.backends"
local log = require "utils.log"
local select = require "agent.ui.select"
local selection = require "agent.selection"

local M = {}

--- Sin ningún backend disponible: en vez de un error seco, ofrece el setup (detecta Ollama, LM Studio...)
function M.none()
  log.error "Agent: no backend available (`claude`, `opencode`, a local Ollama...). Opening setup"
  require("agent.setup").open()
end

---@param tier "main"|"light"? qué modelo se elige (por defecto el principal)
function M.model(tier)
  tier = tier or "main"
  local available = backends.available()
  if #available == 0 then
    return M.none()
  end

  local current = selection.current(tier == "light" and { name = "", tier = "light" } or nil)
  local groups, pending, shown = {}, #available, false

  -- opencode tarda en listar sus modelos la primera vez: avisar si se hace esperar
  vim.defer_fn(function()
    if pending > 0 and not shown then
      log.info "Agent: listing models…"
    end
  end, 300)

  for i, backend in ipairs(available) do
    backend.models(function(models)
      groups[i] = vim.tbl_map(function(m)
        return {
          backend = backend.name,
          model = m.id,
          label = ("%-9s %s"):format(backend.label, m.label or m.id),
          current = current ~= nil and current.backend == backend.name and current.model == m.id,
        }
      end, models)
      pending = pending - 1
      if pending == 0 then
        shown = true
        local items = {}
        for _, group in pairs(groups) do
          vim.list_extend(items, group)
        end
        select.pick(
          items,
          { title = tier == "light" and "Agent · light model (docs, explain)" or "Agent · backend and model" },
          function(choice)
            selection.set(choice.backend, choice.model, tier)
            log.info(("Agent: %s model %s"):format(tier, choice.backend .. "/" .. choice.model))
          end
        )
      end
    end)
  end
end

function M.effort()
  local current = selection.current()
  if not current then
    return M.none()
  end
  local backend = backends.get(current.backend)
  if not backend.efforts then
    return log.info(("Agent: %s has no effort levels"):format(backend.label))
  end

  local items = { { label = "default (the model's own)", value = nil, current = current.effort == nil } }
  for _, level in ipairs(backend.efforts) do
    items[#items + 1] = { label = level, value = level, current = current.effort == level }
  end
  select.pick(items, { title = "Agent · effort (" .. backend.label .. ")" }, function(choice)
    selection.set_effort(choice.value)
    log.info("Agent: effort " .. (choice.value or "default"))
  end)
end

--- Un solo punto de entrada para lo que se cambia poco: modelo principal, ligero y esfuerzo
function M.menu()
  local sel = selection.current()
  if not sel then
    return M.none()
  end
  local light = selection.current { name = "", tier = "light" }
  local items = {
    {
      label = ("Main model    %s"):format(selection.label(sel)),
      run = function()
        M.model "main"
      end,
    },
    {
      label = ("Light model   %s"):format(selection.label(light)),
      run = function()
        M.model "light"
      end,
    },
  }
  if backends.get(sel.backend).efforts then
    items[#items + 1] = { label = ("Effort        %s"):format(sel.effort or "default"), run = M.effort }
  end
  items[#items + 1] = { label = "Setup         backends, local models…", run = require("agent.setup").open }
  select.pick(items, { title = "Agent · settings" }, function(choice)
    choice.run()
  end)
end

return M
