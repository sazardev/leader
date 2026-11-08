-- ── Env: AI loader generation (<leader>Ea) ─────────────────────────────────
-- 0 resident processes: one `agent.complete` one-shot that turns the project's .env.example
-- into the typed loader the language idiom expects. Never overwrites: an existing file is opened.
-- Identical UI in every language (a single key, same prompt shape).
local log = require "utils.log"
local parse = require "env.parse"

local M = {}

---@ The loader target for a language: the file to create when none exists
---@param lang table
---@param root string
---@return string
function M.target(lang, root)
  local rel = lang.loader and lang.loader.target or "config/env"
  return root .. "/" .. rel
end

---@ Prompt for the one-shot: only the .env keys, never the real secrets
---@param lang table
---@param ex_text string
---@return string system, string prompt
function M.prompt(lang, ex_text)
  local keys = parse.keys(parse.parse(ex_text))
  local style = (lang.loader and lang.loader.style) or ""
  local system = table.concat({
    ("You are an expert engineer in %s."):format(lang.label),
    "Create ONE typed config loader file that reads environment variables from a .env file.",
    "Requirements:",
    "- Use the idiomatic library for this language (dotenv/godotenv/pydantic/dotenvy/DotNetEnv/dotenv/flutter_dotenv…).",
    "- Read a .env file plus the real process environment (env wins, .env only as fallback).",
    "- Typed fields for every key below; sensible dev defaults (PORT, HOST, LOG_LEVEL…); required keys fail fast with a message listing the missing ones.",
    "- Export a single entry point (Load/MustLoad, get_settings, env, fromEnv, Env.load…). Do not scatter env reads in business code.",
    "- No comments about the prompt, no hardcoded secrets, no placeholders like <TODO>.",
    style ~= "" and ("Style for this language: " .. style) or nil,
    "Respond with ONLY the file content, no prose, no markdown fences.",
  }, "\n")
  local prompt = table.concat({
    "Project: " .. (lang.label or "generic"),
    "Create the loader file at: " .. (lang.loader and lang.loader.target or "config/env"),
    "Environment keys to map (KEY=value hints from .env.example, values are dummy):",
    ex_text or "",
    "Keys list: " .. table.concat(keys, ", "),
    "Write the complete file now.",
  }, "\n")
  return system, prompt
end

---@ Generate the loader file for `lang` under `root`
---@param root string
---@param lang table
function M.generate(root, lang)
  local ex_path = root .. "/.env.example"
  local ex_text = require("utils.project").read(ex_path)
  if not ex_text then
    return log.warn "Env AI: .env.example is missing — create it first (<leader>En)"
  end
  local target = M.target(lang, root)
  if vim.uv.fs_stat(target) ~= nil then
    log.info(("Env AI: %s already exists, opened it"):format(vim.fs.basename(target)))
    return vim.cmd.edit(vim.fn.fnameescape(target))
  end
  -- warn before spending
  local ok, agent = pcall(require, "agent")
  if not ok or not agent.complete then
    return log.warn "Env AI: agent backend not available"
  end
  local system, prompt = M.prompt(lang, ex_text)
  log.info("Env AI: generating " .. vim.fs.basename(target) .. " …")
  agent.complete({
    action = "env_loader",
    system = system,
    prompt = prompt,
    tier = "main",
    timeout_ms = 180000,
  }, function(ok, text, usage)
    if not ok then
      return log.warn("Env AI: " .. tostring(text))
    end
    local body = (text or ""):gsub("^```%w*\n", ""):gsub("\n```%s*$", "")
    if vim.trim(body) == "" then
      return log.warn "Env AI: empty answer"
    end
    vim.fn.mkdir(vim.fs.dirname(target), "p")
    local f, err = io.open(target, "w")
    if not f then
      return log.warn("Env AI: " .. tostring(err))
    end
    f:write(body:gsub("%s+$", "") .. "\n")
    f:close()
    vim.cmd.edit(vim.fn.fnameescape(target))
    local extra = usage and usage.total and (" · %d tok"):format(usage.total) or ""
    log.info(("Env AI: created %s%s"):format(target:sub(#root + 2), extra))
    -- reminder: ensure .gitignore covers loader secrets? No, loader is committed.
  end)
end

return M
