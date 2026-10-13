-- ── Setup report (markdown) ──────────────────────────────────────────────────
-- Turns the `detect` snapshot + the recommendation into readable text. Pure: works the same for the nvim panel and for the
-- terminal (scripts/agent-setup.sh).
local M = {}

local OK, NO = "✔", "✘"

---@param snap AgentSnapshot
---@param rec AgentRecommendation
---@param current string?  current selection ("ollama/qwen2.5-coder:7b")
---@return string[]
function M.build(snap, rec, current)
  local out = { "# Agent setup", "" }
  if current then
    out[#out + 1] = ("Active: **%s**"):format(current)
    out[#out + 1] = ""
  end

  out[#out + 1] = "## Agent CLIs"
  for _, cli in ipairs(snap.clis) do
    out[#out + 1] = cli.path and ("- %s `%s` %s — %s"):format(OK, cli.name, cli.version or "", cli.role)
      or ("- %s `%s` — %s"):format(NO, cli.name, cli.role)
  end
  if #snap.custom > 0 then
    out[#out + 1] = ("- custom backends in settings: %s"):format(table.concat(snap.custom, ", "))
  end

  out[#out + 1] = ""
  out[#out + 1] = "## Local model servers"
  if #snap.ollama_servers == 0 and #snap.openai_servers == 0 then
    out[#out + 1] = "- none answering (looked at 127.0.0.1 and, in WSL/Docker, the Windows host)"
  end
  for _, s in ipairs(snap.ollama_servers) do
    out[#out + 1] = ("- %s Ollama %s at `%s` — %d model(s)"):format(OK, s.version or "?", s.url, #s.models)
    for _, m in ipairs(s.models) do
      local extra = {}
      if m.params then
        extra[#extra + 1] = m.params
      end
      if m.quant then
        extra[#extra + 1] = m.quant
      end
      if m.size then
        extra[#extra + 1] = ("%.1f GB"):format(m.size / 1e9)
      end
      out[#out + 1] = ("  - `%s` %s"):format(m.name, #extra > 0 and ("(" .. table.concat(extra, " · ") .. ")") or "")
    end
    for _, m in ipairs(s.loaded) do
      local where = (m.vram or 0) >= (m.size or 1) * 0.99 and "GPU" or ((m.vram or 0) > 0 and "GPU+CPU" or "CPU")
      out[#out + 1] = ("  - loaded now: `%s` on %s"):format(m.name, where)
    end
  end
  for _, s in ipairs(snap.openai_servers) do
    out[#out + 1] = ("- %s OpenAI-compatible at `%s` — %s"):format(
      OK,
      s.url,
      #s.models > 0 and table.concat(s.models, ", ") or "no models listed"
    )
  end

  out[#out + 1] = ""
  out[#out + 1] = "## Hardware"
  out[#out + 1] = snap.gpu
      and ("- GPU: %s · %.1f GB VRAM (Ollama uses CUDA automatically)"):format(snap.gpu.name, snap.gpu.vram_gb)
    or "- GPU: none detected (`nvidia-smi` not found) — local models run on CPU"
  if snap.ram_gb then
    out[#out + 1] = ("- RAM: %.1f GB"):format(snap.ram_gb)
  end

  local missing_ollama = #snap.ollama_servers == 0
  if missing_ollama then
    out[#out + 1] = ""
    out[#out + 1] = "## Get Ollama"
    local ollama = vim.tbl_filter(function(c)
      return c.name == "ollama"
    end, snap.clis)[1]
    if ollama and ollama.path then
      out[#out + 1] = "- installed but not running: start it from this menu (`Start Ollama`) or `ollama serve`"
    else
      out[#out + 1] = "- install: https://ollama.com/download (Linux: `curl -fsSL https://ollama.com/install.sh | sh`)"
    end
    if snap.docker then
      out[#out + 1] =
        "- or with Docker (NVIDIA): `docker run -d --gpus all -p 11434:11434 -v ollama:/root/.ollama ollama/ollama`"
    end
    out[#out + 1] =
      "- WSL2 + Windows Ollama: set `OLLAMA_HOST=0.0.0.0` on Windows so WSL can reach it (detected automatically)"
  end

  if rec.light or rec.main or #rec.pulls > 0 or #rec.notes > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "## Recommendation"
    if rec.main then
      out[#out + 1] = ("- main: `%s/%s`"):format(rec.main.backend, rec.main.model)
    end
    if rec.light then
      out[#out + 1] = ("- light (docs, explain): `%s/%s`"):format(rec.light.backend, rec.light.model)
    end
    for _, p in ipairs(rec.pulls) do
      out[#out + 1] = ("- pull `%s` — %s"):format(p.model, p.why)
    end
    for _, n in ipairs(rec.notes) do
      out[#out + 1] = "- note: " .. n
    end
  end

  if #snap.warnings > 0 then
    out[#out + 1] = ""
    out[#out + 1] = "## Warnings"
    for _, w in ipairs(snap.warnings) do
      out[#out + 1] = "- " .. w
    end
  end
  return out
end

--- Is at least one backend ready to use? (cloud CLI, or a local server with models)
---@param snap AgentSnapshot
---@return boolean
function M.ready(snap)
  for _, cli in ipairs(snap.clis) do
    if cli.path and (cli.name == "claude" or cli.name == "opencode") then
      return true
    end
  end
  for _, s in ipairs(snap.ollama_servers) do
    if #s.models > 0 then
      return true
    end
  end
  for _, s in ipairs(snap.openai_servers) do
    if #s.models > 0 then
      return true
    end
  end
  return #snap.custom > 0
end

return M
