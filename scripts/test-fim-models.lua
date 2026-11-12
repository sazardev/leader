-- Tests of the FIM model catalog and hardware detection (nvim/lua/fim/models.lua, hardware.lua): the device parser,
-- the dGPU/iGPU classifier, the recommendation by VRAM, what the picker offers and how the current model matches.
-- Hermetic: no plugins, no config, no network.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-fim-models.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print(("FAIL %s\n  got:  %s\n  want: %s"):format(name, vim.inspect(got), vim.inspect(want)))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end
local function group(title)
  print("\n── " .. title .. " ──")
end

local hardware = require "fim.hardware"
local models = require "fim.models"

-- ── device parser ────────────────────────────────────────────────────────────
group("devices")
local laptop = hardware.parse_devices(
  "Available devices:\n  Vulkan0: Intel(R) Iris(R) Xe Graphics (TGL GT2) (11783 MiB, 9772 MiB free)\n"
)
eq("devices: one line", #laptop, 1)
eq("devices: name keeps the card's own parentheses", laptop[1].name, "Intel(R) Iris(R) Xe Graphics (TGL GT2)")
eq("devices: vram", laptop[1].vram_mb, 11783)

local desktop = hardware.parse_devices(
  "Available devices:\n"
    .. "  CUDA0: NVIDIA GeForce RTX 3060 (12288 MiB, 11800 MiB free)\n"
    .. "  Vulkan0: NVIDIA GeForce RTX 3060 (12288 MiB, 11800 MiB free)\n"
)
eq("devices: CUDA and Vulkan both listed", #desktop, 2)
eq("devices: desktop name", desktop[1].name, "NVIDIA GeForce RTX 3060")
eq("devices: no devices", hardware.parse_devices "Available devices:\n  (none)\n", {})

-- ── classifier ───────────────────────────────────────────────────────────────
group("classify")
ok("igpu: Iris Xe", hardware.is_igpu "Intel(R) Iris(R) Xe Graphics (TGL GT2)")
ok("igpu: AMD Radeon Graphics", hardware.is_igpu "AMD Radeon(TM) Graphics")
ok("igpu: Apple Silicon", hardware.is_igpu "Apple M3 Pro")
ok("igpu: software renderer", hardware.is_igpu "llvmpipe (LLVM 19.1.7, 256 bits)")
ok("igpu: an RTX is not one", not hardware.is_igpu "NVIDIA GeForce RTX 3060")
ok("dgpu: RTX", hardware.is_dgpu "NVIDIA GeForce RTX 3060")
ok("dgpu: Radeon RX", hardware.is_dgpu "AMD Radeon RX 6800 XT")
ok("dgpu: Arc", hardware.is_dgpu "Intel(R) Arc(TM) A770 Graphics")
ok("dgpu: an Iris Xe is not one", not hardware.is_dgpu "Intel(R) Iris(R) Xe Graphics (TGL GT2)")

local lap = hardware.classify(laptop)
eq("classify: laptop has an iGPU", lap.igpu and lap.igpu.name, "Intel(R) Iris(R) Xe Graphics (TGL GT2)")
eq("classify: laptop has no dGPU", lap.dgpu, nil)
local desk = hardware.classify(desktop)
eq("classify: desktop dGPU", desk.dgpu and desk.dgpu.name, "NVIDIA GeForce RTX 3060")
eq("classify: duplicate CUDA/Vulkan is one card", desk.dgpu and desk.dgpu.vram_mb, 12288)
eq("classify: desktop has no iGPU", desk.igpu, nil)
local both = hardware.classify {
  { name = "Intel(R) Iris(R) Xe Graphics", vram_mb = 11783 },
  { name = "NVIDIA GeForce RTX 3060", vram_mb = 12288 },
}
eq("classify: both cards", { both.igpu.name, both.dgpu.name }, { "Intel(R) Iris(R) Xe Graphics", "NVIDIA GeForce RTX 3060" })

-- ── summary ──────────────────────────────────────────────────────────────────
group("summary")
eq(
  "summary: iGPU and RAM",
  hardware.summary { igpu = { name = "Intel Iris Xe", vram_mb = 11783 }, ram_mb = 16000 },
  "Intel Iris Xe (iGPU) · 16 GB RAM"
)
eq(
  "summary: dGPU VRAM and RAM",
  hardware.summary { dgpu = { name = "RTX 3060", vram_mb = 12288 }, ram_mb = 32768 },
  "RTX 3060 (12 GB VRAM) · 32 GB RAM"
)
eq("summary: CPU only", hardware.summary {}, "CPU only")
eq("summary: CPU and RAM", hardware.summary { ram_mb = 8192 }, "CPU only · 8 GB RAM")

-- ── catalog ──────────────────────────────────────────────────────────────────
group("catalog")
local ids = {}
for _, entry in ipairs(models.catalog) do
  ok("catalog: " .. entry.id .. " has an id", type(entry.id) == "string" and #entry.id > 0)
  ok("catalog: " .. entry.id .. " has a label", type(entry.label) == "string" and #entry.label > 0)
  ok("catalog: " .. entry.id .. " has a size", type(entry.size_mb) == "number" and entry.size_mb > 0)
  ok("catalog: " .. entry.id .. " is CPU or GPU", entry.gpu_layers == 0 or entry.gpu_layers == 99)
  if entry.gpu_layers == 0 then
    ok("catalog: " .. entry.id .. " is offered without a dGPU", models.available({})[1] ~= nil)
  else
    ok("catalog: " .. entry.id .. " declares VRAM", type(entry.min_vram_mb) == "number")
  end
  if not entry.preset then
    ok("catalog: " .. entry.id .. " has a repo", type(entry.repo) == "string" and #entry.repo > 0)
    ok("catalog: " .. entry.id .. " has a file", type(entry.file) == "string" and #entry.file > 0)
  end
  ok("catalog: " .. entry.id .. " is unique", not ids[entry.id])
  ids[entry.id] = true
end
eq("catalog: six models", #models.catalog, 6)
eq("catalog: the 1.5B entries share the preset", { models.by_id("qwen15_cpu").preset, models.by_id("qwen15_gpu").preset }, { true, true })
eq("catalog: unknown id", models.by_id "nope", nil)

-- ── recommendation ───────────────────────────────────────────────────────────
group("recommend")
eq("recommend: no GPU", models.recommend {}, "qwen05_cpu")
eq("recommend: iGPU", models.recommend { igpu = { name = "Iris Xe", vram_mb = 11783 } }, "qwen05_cpu")
eq("recommend: 1 GB", models.recommend { dgpu = { vram_mb = 1024 } }, "qwen05_gpu")
eq("recommend: 2 GB", models.recommend { dgpu = { vram_mb = 2048 } }, "qwen05_gpu")
eq("recommend: 3 GB", models.recommend { dgpu = { vram_mb = 3072 } }, "qwen15_gpu")
eq("recommend: 4 GB", models.recommend { dgpu = { vram_mb = 4096 } }, "qwen15_gpu")
eq("recommend: 6 GB", models.recommend { dgpu = { vram_mb = 6144 } }, "qwen3_gpu")
eq("recommend: 8 GB", models.recommend { dgpu = { vram_mb = 8192 } }, "qwen3_gpu")
eq("recommend: 10 GB", models.recommend { dgpu = { vram_mb = 10240 } }, "qwen7_gpu")
eq("recommend: 12 GB", models.recommend { dgpu = { vram_mb = 12288 } }, "qwen7_gpu")

-- ── what the picker offers ───────────────────────────────────────────────────
group("available")
for _, case in ipairs {
  { name = "no GPU", hw = {}, n = 2 },
  { name = "iGPU", hw = { igpu = { name = "Iris Xe", vram_mb = 11783 } }, n = 2 },
  { name = "2 GB dGPU", hw = { dgpu = { vram_mb = 2048 } }, n = 3 },
  { name = "4 GB dGPU", hw = { dgpu = { vram_mb = 4096 } }, n = 4 },
  { name = "6 GB dGPU", hw = { dgpu = { vram_mb = 6144 } }, n = 5 },
  { name = "12 GB dGPU", hw = { dgpu = { vram_mb = 12288 } }, n = 6 },
} do
  local list = models.available(case.hw)
  eq("available: " .. case.name, #list, case.n)
  local recommended = models.by_id(models.recommend(case.hw))
  ok("available: " .. case.name .. " includes the recommendation", vim.iter(list):any(function(e)
    return e.id == recommended.id
  end))
end
eq("available: laptop first entry", models.available({ igpu = { name = "Iris Xe", vram_mb = 11783 } })[1].id, "qwen05_cpu")

-- ── the model in settings ────────────────────────────────────────────────────
group("current")
eq("current: preset GPU", models.current_id { model = "preset", gpu_layers = 99 }, "qwen15_gpu")
eq("current: preset CPU", models.current_id { model = "preset", gpu_layers = 0 }, "qwen15_cpu")
eq("current: nil is the preset", models.current_id { model = nil, gpu_layers = 99 }, "qwen15_gpu")
eq("current: local 0.5B CPU", models.current_id { model = "/x/qwen2.5-coder-0.5b-q8_0.gguf", gpu_layers = 0 }, "qwen05_cpu")
eq("current: local 0.5B GPU", models.current_id { model = "/x/qwen2.5-coder-0.5b-q8_0.gguf", gpu_layers = 99 }, "qwen05_gpu")
eq(
  "current: HF 7B",
  models.current_id {
    model = { repo = "ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF", file = "qwen2.5-coder-7b-q8_0.gguf" },
    gpu_layers = 99,
  },
  "qwen7_gpu"
)
eq("current: unknown path", models.current_id { model = "/x/other.gguf", gpu_layers = 99 }, nil)
eq("current: unknown repo", models.current_id { model = { repo = "x", file = "y" }, gpu_layers = 99 }, nil)

-- ── model_for and the local copy ────────────────────────────────────────────
group("model_for")
eq("model_for: preset", models.model_for(models.by_id "qwen15_gpu"), "preset")
eq(
  "model_for: remote model",
  models.model_for(models.by_id "qwen7_gpu", function()
    return false
  end),
  { repo = "ggml-org/Qwen2.5-Coder-7B-Q8_0-GGUF", file = "qwen2.5-coder-7b-q8_0.gguf" }
)
local local_path = vim.fs.joinpath(vim.fn.stdpath "data", "fim", "qwen2.5-coder-0.5b-q8_0.gguf")
eq(
  "model_for: a local copy wins",
  models.model_for(models.by_id "qwen05_cpu", function()
    return true
  end),
  local_path
)
eq("model_for: no local copy", models.local_path(models.by_id "qwen05_cpu", function()
  return false
end), nil)
eq("model_for: preset has no local copy", models.local_path(models.by_id "qwen15_gpu", function()
  return true
end), nil)

print(("\nALL OK (%d checks)"):format(total))
if fails > 0 then
  vim.cmd "cq 1"
end
