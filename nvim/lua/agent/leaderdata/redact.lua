-- ── Turning what Leader knows into what may be recorded (pure) ───────────────
-- Names, paths and text are the person's; sizes, counts, durations and outcomes are Leader's. Here the first become the second:
-- a path is a salted hash (stable inside one project so "this file failed three times" can be counted, useless anywhere else),
-- a length is a bucket, an error is a class. The salt lives in the project's own .leader/ and is never exported.
local M = {}

---@param salt string
---@param text string
---@return string 8 hex digits
function M.hash(salt, text)
  return vim.fn.sha256(salt .. "\0" .. text):sub(1, 8)
end

---@param n integer?
---@return "<50"|"<200"|"<500"|"500+"
function M.bucket(n)
  n = n or 0
  if n < 50 then
    return "<50"
  elseif n < 200 then
    return "<200"
  elseif n < 500 then
    return "<500"
  end
  return "500+"
end

--- The extension of a path, lowercase, "" when it has none
---@param path string
---@return string
function M.ext(path)
  return ((path:match "%.([%w]+)$") or ""):lower()
end

--- A random id (8 hex digits)
---@return string
function M.random_id()
  return vim.fn.sha256(tostring(vim.uv.hrtime()) .. tostring(math.random()) .. tostring(os.time())):sub(1, 8)
end

--- The backends Leader ships with: their names say nothing about the user. A custom backend (`settings.agent.custom`) is named by the
--- user and may be an internal tool, so neither its name nor its models are recorded
local KNOWN_BACKENDS = { claude = true, opencode = true, ollama = true, openai = true, replay = true }

---@param backend string?
---@return boolean
function M.known_backend(backend)
  return KNOWN_BACKENDS[backend or ""] == true
end

--- A `backend/model` label, only when the backend is one Leader ships with (nil otherwise)
---@param label string?
---@return string?
function M.model_label(label)
  local backend = (label or ""):match "^([^/]+)/"
  return backend and KNOWN_BACKENDS[backend] and label or nil
end

local LANGS = {
  dart = "dart",
  typescript = "ts",
  javascript = "ts",
  typescriptreact = "ts",
  javascriptreact = "ts",
  go = "go",
  rust = "rust",
  python = "py",
  java = "jvm",
  kotlin = "jvm",
  scala = "jvm",
  swift = "swift",
  lua = "lua",
} -- stylua: ignore

--- A filetype as one of the families the schema knows
---@param filetype string?
---@return string
function M.lang(filetype)
  return LANGS[filetype or ""] or "other"
end

return M
