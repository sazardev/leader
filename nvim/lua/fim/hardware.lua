-- ── FIM hardware detection ──────────────────────────────────────────────────
-- What llama.cpp can actually use on this machine: `llama-server --list-devices` (the same binary the completion
-- server runs) plus the system RAM. Parsers and classifiers are pure; `collect` is the only impure part.
local M = {}

---@param name string
---@return boolean
function M.is_igpu(name)
  local n = (name or ""):lower()
  return n:find("iris", 1, true) ~= nil
    or n:find("uhd", 1, true) ~= nil
    or n:find("hd graphics", 1, true) ~= nil
    or n:find("radeon(tm) graphics", 1, true) ~= nil
    or n:find("radeon graphics", 1, true) ~= nil
    or (n:find("vega", 1, true) ~= nil and n:find("graphics", 1, true) ~= nil)
    or n:find("apple m", 1, true) ~= nil
    or n:find("llvmpipe", 1, true) ~= nil
    or n:find("basic render", 1, true) ~= nil
end

---@param name string
---@return boolean
function M.is_dgpu(name)
  local n = (name or ""):lower()
  return n:find("nvidia", 1, true) ~= nil
    or n:find("geforce", 1, true) ~= nil
    or n:find("rtx", 1, true) ~= nil
    or n:find("gtx", 1, true) ~= nil
    or n:find("quadro", 1, true) ~= nil
    or n:find("tesla", 1, true) ~= nil
    or n:find "radeon.*rx" ~= nil
    or n:find("radeon pro", 1, true) ~= nil
    or n:find "arc.*a%d" ~= nil
    or n:find "arc.*b%d" ~= nil
    or n:find("arc pro", 1, true) ~= nil
end

--- `llama-server --list-devices` output → `{ name, vram_mb }` per device.
---@param text string?
---@return { name: string, vram_mb: integer }[]
function M.parse_devices(text)
  local out = {}
  for line in (text or ""):gmatch "[^\n]+" do
    local name, mb = line:match "^%s*[%w_]+:%s+(.-)%s+%((%d+) MiB"
    if name then
      out[#out + 1] = { name = name, vram_mb = tonumber(mb) }
    end
  end
  return out
end

--- The biggest dedicated and integrated GPU the list has (CUDA and Vulkan may list the same card twice).
---@param devices { name: string, vram_mb: integer }[]
---@return { devices: table[], dgpu: table?, igpu: table? }
function M.classify(devices)
  local info = { devices = devices }
  for _, device in ipairs(devices) do
    if M.is_igpu(device.name) then
      if not info.igpu or device.vram_mb > info.igpu.vram_mb then
        info.igpu = device
      end
    elseif M.is_dgpu(device.name) then
      if not info.dgpu or device.vram_mb > info.dgpu.vram_mb then
        info.dgpu = device
      end
    end
  end
  return info
end

---@return integer
function M.ram_mb()
  local sys = vim.uv.os_uname().sysname
  if sys == "Linux" then
    local f = io.open("/proc/meminfo", "r")
    if f then
      local text = f:read "*a"
      f:close()
      local kb = tonumber(text:match "MemTotal:%s*(%d+)")
      if kb then
        return math.floor(kb / 1024)
      end
    end
  elseif sys == "Darwin" then
    local bytes = tonumber(vim.fn.system { "sysctl", "-n", "hw.memsize" })
    if bytes then
      return math.floor(bytes / 1024 / 1024)
    end
  end
  return 0
end

---@param info table
---@return string
function M.summary(info)
  local parts = {}
  if info.dgpu then
    parts[#parts + 1] = ("%s (%d GB VRAM)"):format(info.dgpu.name, math.floor(info.dgpu.vram_mb / 1024 + 0.5))
  elseif info.igpu then
    parts[#parts + 1] = info.igpu.name .. " (iGPU)"
  else
    parts[#parts + 1] = "CPU only"
  end
  if info.ram_mb and info.ram_mb > 0 then
    parts[#parts + 1] = ("%d GB RAM"):format(math.floor(info.ram_mb / 1024 + 0.5))
  end
  return table.concat(parts, " · ")
end

--- Reads the devices llama.cpp can use and the system RAM, then calls `cb(info)`. It never blocks the editor.
---@param cb fun(info: table)
function M.collect(cb)
  local info = { devices = {}, ram_mb = M.ram_mb() }
  if vim.fn.executable "llama-server" == 0 then
    info.note = "llama-server is not installed (install llama.cpp first)"
    info.summary = "llama-server not found"
    return cb(info)
  end
  vim.system({ "llama-server", "--list-devices" }, { text = true, timeout = 5000 }, function(out)
    vim.schedule(function()
      info.devices = M.parse_devices(out.stdout or "")
      local devices = M.classify(info.devices)
      info.dgpu, info.igpu = devices.dgpu, devices.igpu
      -- a GPU the binary cannot offload to is not a GPU this picker can use; say why the list has no dGPU entries
      if not info.dgpu and vim.fn.executable "nvidia-smi" == 1 then
        local text = vim.fn.system { "nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader,nounits" }
        if vim.v.shell_error == 0 and text and text:match "%S" then
          info.note = "NVIDIA GPU found, but llama.cpp is not using it (install ggml-cuda or ggml-vulkan)"
        end
      end
      info.summary = M.summary(info)
      cb(info)
    end)
  end)
end

return M
