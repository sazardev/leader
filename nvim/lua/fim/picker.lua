-- ── Local completion model picker ───────────────────────────────────────────
-- A flat modal (utils.modal) with the models this machine can run. The detected GPU/VRAM picks the recommended one;
-- Enter saves the choice in prefs, restarts the server and turns FIM on. A model already under `stdpath("data")/fim`
-- is used from disk; the rest are downloaded by llama-server (`-hf`) on the first start.
local hardware = require "fim.hardware"
local models = require "fim.models"
local modal = require "utils.modal"
local log = require "utils.log"

local M = {}

--- The recommended entry first: the checklist starts on it, so Enter does the right thing.
---@param info table
---@return table[], string
local function options(info)
  local recommended = models.recommend(info)
  local ordered = {}
  for _, entry in ipairs(models.available(info)) do
    if entry.id == recommended then
      table.insert(ordered, 1, entry)
    else
      ordered[#ordered + 1] = entry
    end
  end
  return ordered, recommended
end

---@param info table
---@param opts { on_cancel?: fun() }
local function open(info, opts)
  local list, recommended = options(info)
  local current = models.current_id() or recommended
  local items = {}
  for _, entry in ipairs(list) do
    items[#items + 1] = {
      label = entry.label,
      desc = entry.desc .. (entry.id == recommended and " · recommended" or ""),
      checked = entry.id == current,
      group = "Model",
    }
  end
  local rec = models.by_id(recommended)
  local intro = {
    { { "Detected: ", modal.hl.muted }, { info.summary, modal.hl.file } },
    { { "Recommended: ", modal.hl.muted }, { rec and rec.label or "?", modal.hl.mark } },
  }
  if info.note then
    intro[#intro + 1] = { { "  " .. info.note, modal.hl.warn } }
  end
  if not info.dgpu and info.igpu then
    intro[#intro + 1] = { { "  iGPU only: the CPU is faster for these small models.", modal.hl.muted } }
  end
  intro[#intro + 1] = ""

  modal.checklist(items, {
    title = "Local completion model",
    intro = intro,
    exclusive = { Model = true },
    clean = true,
    confirm = "Install & use",
    footer = "Enter applies and restarts · first start downloads the model",
    on_cancel = opts.on_cancel,
  }, function(chosen)
    local entry = chosen[1] and list[chosen[1]]
    if not entry then
      log.info "FIM: no model chosen"
      if opts.on_cancel then
        opts.on_cancel()
      end
      return
    end
    local model = models.model_for(entry)
    log.info(
      ("FIM: %s (%d MB); restarting the server%s"):format(
        entry.label,
        entry.size_mb,
        type(model) == "table" and "; it downloads on the first start" or ""
      )
    )
    require("fim").use(model, entry.gpu_layers)
  end)
end

--- Opens the picker after detecting this machine. `opts.on_cancel` runs when no model is chosen (Esc, q or Enter on an
--- empty list), so a caller that was enabling FIM can leave it off.
---@param opts { on_cancel?: fun() }?
function M.open(opts)
  opts = opts or {}
  if vim.fn.executable "llama-server" == 0 then
    log.warn "FIM: install llama.cpp first (llama-server is not in PATH)"
    if opts.on_cancel then
      opts.on_cancel()
    end
    return
  end
  if #vim.api.nvim_list_uis() == 0 then
    if opts.on_cancel then
      opts.on_cancel()
    end
    return
  end
  hardware.collect(function(info)
    open(info, opts)
  end)
end

return M
