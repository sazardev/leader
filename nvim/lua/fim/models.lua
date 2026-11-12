-- ── Local FIM models ─────────────────────────────────────────────────────────
-- The catalog the picker offers and (pure) what fits this machine. `preset` entries use llama.cpp's
-- `--fim-qwen-<n>b-default` (it selects the file and the FIM tuning); the others are `repo`/`file` GGUF downloads.
-- `gpu_layers = 0` keeps a model on the CPU (faster on iGPUs); 99 offloads every layer.
local M = {}

---@class FimModel
---@field id string
---@field label string
---@field desc string
---@field size_mb integer
---@field gpu_layers integer
---@field min_vram_mb integer?
---@field preset boolean?
---@field repo string?
---@field file string?

--- Fastest/smallest first; the picker moves the recommended one to the top. A GPU entry is offered only when the
--- detected dedicated GPU has at least `min_vram_mb`.
---@type FimModel[]
M.catalog = {
  {
    id = "qwen05_cpu",
    label = "0.5B Q8 · CPU",
    desc = "507 MB · ~40 tok/s · fastest",
    size_mb = 507,
    gpu_layers = 0,
    repo = "ggml-org/Qwen2.5-Coder-0.5B-Q8_0-GGUF",
    file = "qwen2.5-coder-0.5b-q8_0.gguf",
  },
  {
    id = "qwen15_cpu",
    label = "1.5B Q8 · CPU",
    desc = "1.6 GB · ~12 tok/s · more quality",
    size_mb = 1646,
    gpu_layers = 0,
    preset = true,
  },
  {
    id = "qwen05_gpu",
    label = "0.5B Q8 · GPU",
    desc = "507 MB · fastest on a dedicated GPU",
    size_mb = 507,
    gpu_layers = 99,
    min_vram_mb = 1024,
    repo = "ggml-org/Qwen2.5-Coder-0.5B-Q8_0-GGUF",
    file = "qwen2.5-coder-0.5b-q8_0.gguf",
  },
  {
    id = "qwen15_gpu",
    label = "1.5B Q8 · GPU",
    desc = "1.6 GB · good quality on 3 GB+ VRAM",
    size_mb = 1646,
    gpu_layers = 99,
    min_vram_mb = 3072,
    preset = true,
  },
  {
    id = "qwen3_gpu",
    label = "3B Q8 · GPU",
    desc = "3.3 GB · better quality on 5 GB+ VRAM",
    size_mb = 3300,
    gpu_layers = 99,
    min_vram_mb = 5120,
    repo = "ggml-org/Qwen2.5-Coder-3B-Q8_0-GGUF",
    file = "qwen2.5-coder-3b-q8_0.gguf",
  },
  {
    id = "qwen7_gpu",
    label = "7B Q8 · GPU",
    desc = "8.1 GB · best quality on 10 GB+ VRAM",
    size_mb = 8100,
    gpu_layers = 99,
    min_vram_mb = 10240,
    repo = "ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF",
    file = "qwen2.5-coder-7b-q8_0.gguf",
  },
}

---@param id string
---@return FimModel?
function M.by_id(id)
  for _, model in ipairs(M.catalog) do
    if model.id == id then
      return model
    end
  end
end

--- The model this machine should use. A dedicated GPU wins by VRAM; without one the CPU runs the 0.5B, which measured
--- faster than Vulkan on an Iris Xe (and far faster than the 1.5B).
---@param hw table from fim.hardware.collect
---@return string
function M.recommend(hw)
  local vram = hw.dgpu and hw.dgpu.vram_mb or 0
  if vram >= 10240 then
    return "qwen7_gpu"
  elseif vram >= 5120 then
    return "qwen3_gpu"
  elseif vram >= 3072 then
    return "qwen15_gpu"
  elseif vram >= 1024 then
    return "qwen05_gpu"
  end
  return "qwen05_cpu"
end

--- The entries this machine can run: every CPU entry, and the GPU ones that fit the detected dedicated GPU.
---@param hw table
---@return FimModel[]
function M.available(hw)
  local out = {}
  for _, model in ipairs(M.catalog) do
    if model.gpu_layers == 0 or (hw.dgpu and hw.dgpu.vram_mb >= (model.min_vram_mb or 0)) then
      out[#out + 1] = model
    end
  end
  return out
end

--- The id of the catalog entry `settings.fim` is already using (nil when it is a model the catalog does not know).
---@param fim_cfg table? `settings.fim`; injectable for tests
---@return string?
function M.current_id(fim_cfg)
  local cfg = fim_cfg or require("core.settings").fim
  local model = cfg.model
  local layers = cfg.gpu_layers or 99
  for _, entry in ipairs(M.catalog) do
    local same
    if entry.preset then
      same = model == nil or model == "" or model == "preset"
    elseif type(model) == "string" then
      same = vim.fs.basename(vim.fn.expand(model)) == entry.file
    elseif type(model) == "table" then
      same = model.repo == entry.repo and model.file == entry.file
    end
    if same and (entry.gpu_layers == 0) == (layers == 0) then
      return entry.id
    end
  end
end

--- A model already copied under `stdpath("data")/fim` is used from disk instead of downloading it.
---@param entry FimModel
---@param exists fun(path: string): boolean? injectable for tests
---@return string?
function M.local_path(entry, exists)
  if entry.preset or not entry.file then
    return nil
  end
  local path = vim.fs.joinpath(vim.fn.stdpath "data", "fim", entry.file)
  local found = exists and exists(path) or vim.uv.fs_stat(path) ~= nil
  return found and path or nil
end

--- What `settings.fim.model` should hold for `entry`: "preset", a local path, or `{ repo, file }` for `-hf`.
---@param entry FimModel
---@param exists fun(path: string): boolean? injectable for tests
---@return string|table
function M.model_for(entry, exists)
  if entry.preset then
    return "preset"
  end
  return M.local_path(entry, exists) or { repo = entry.repo, file = entry.file }
end

return M
