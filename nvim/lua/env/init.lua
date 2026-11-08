-- ── Env kit (<leader>E) ─────────────────────────────────────────────────────
-- Manages the project's environment files without tokens: it detects the stack from the markers under the git root
-- (go.mod, package.json, pyproject.toml, Cargo.toml, *.csproj…), creates the .env.example the language wants with the
-- .gitignore that keeps secrets out, and checks that every real file still has the keys the example promises.
-- Environments are first-class (.env, .env.dev, .env.qa, .env.staging, .env.prod, …) — same keys, same flow, any language.
-- The AI piece (`<leader>Ea`) is a one-shot `agent.complete` that generates the typed loader (internal/config/env.go,
-- src/config/env.ts, src/config/env.py, src/config.rs, Config/Env.cs…), one file, no prose. See env/ai.lua.
local log = require "utils.log"
local detect = require "env.detect"
local parse = require "env.parse"

local M = {}

---@ Default environments the pickers suggest (besides the local .env)
M.DEFAULT_ENVS = { "dev", "qa", "staging", "prod", "test", "local" }

-- ── root / language ────────────────────────────────────────────────────────

---@ The git root at or above `dir` (or the nearest folder with .git, else the folder itself)
---@param dir string?
---@return string
function M.root(dir)
  dir = dir or require("utils.project").file_dir()
  return vim.fs.root(dir, ".git") or dir
end

---@ The detected preset for a root (falls back to generic)
---@param root string
---@return table
function M.lang(root)
  return detect.primary(root)
end

---@ Every preset that matches this project, plus generic at the end
---@param root string
---@return table[]
function M.candidates(root)
  local out = detect.detected(root)
  local g = detect.lang "generic"
  if g then
    out[#out + 1] = g
  end
  return out
end

-- ── gitignore ──────────────────────────────────────────────────────────────

---@ Adds the secrets rules if the project's .gitignore lacks them (never removes)
---@param root string
function M.ensure_gitignore(root)
  local cfg = require("core.settings").env or {}
  if cfg.ensure_gitignore == false then
    return
  end
  local ok, presets = pcall(require, "gitignore.presets")
  if not ok then
    return
  end
  local secrets
  for _, p in ipairs(presets.list()) do
    if p.name == "secrets" then
      secrets = p
      break
    end
  end
  if not secrets then
    return
  end
  local existing = require("utils.project").read(root .. "/.gitignore")
  local compose = require "gitignore.compose"
  local seen = existing and compose.rules(existing) or nil
  if seen and compose.missing(secrets, seen) == 0 then
    return
  end
  local gitignore = require "gitignore"
  local path, added, why = gitignore.write(root, { secrets })
  if path then
    log.info("Env: .gitignore updated (" .. tostring(added) .. " secrets rule" .. (added == 1 and "" or "s") .. ")")
  elseif why then
    -- "nothing to add" is silent
  end
end

-- ── create ─────────────────────────────────────────────────────────────────

---@ Writes a file without overwriting; opens it when it already exists
---@param root string
---@param rel string absolute or relative to root
---@param body string
---@return string? path, boolean created
local function write_file(root, rel, body)
  local path = rel:sub(1, 1) == "/" and rel or (root .. "/" .. rel)
  if vim.uv.fs_stat(path) ~= nil then
    return path, false
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f, err = io.open(path, "w")
  if not f then
    log.warn("Env: " .. tostring(err))
    return nil, false
  end
  f:write(body:gsub("%s+$", "") .. "\n")
  f:close()
  return path, true
end

---@ The .env.example body for a language (vars filled from the project)
---@param lang table
---@param root string
---@return string
local function example_body(lang, root)
  local v = {}
  local ok, vars = pcall(lang.vars, root)
  if ok and type(vars) == "table" then
    v = vars
  end
  local ok2, body = pcall(lang.template, v)
  if ok2 and body then
    return body
  end
  return "# .env.example\nAPP_ENV=development\nPORT=8080\n"
end

---@ Creates .env.example + .env for a chosen language (never overwrites)
---@param root string
---@param lang table
function M.create_for(root, lang)
  local body = example_body(lang, root)
  local ex_path, ex_created = write_file(root, ".env.example", body)
  -- .env is the local copy: same keys, comment says copy from example
  local local_body =
    body:gsub("^# $$%.env%.example[^\n]*\n", "# .env — local secrets, never commit. Copied from .env.example\n")
  local env_path, env_created = write_file(root, ".env", local_body)
  M.ensure_gitignore(root)
  if ex_created or env_created then
    local made = {}
    if ex_created then
      made[#made + 1] = ".env.example"
    end
    if env_created then
      made[#made + 1] = ".env"
    end
    log.info(
      ("Env (%s): created %s — fill real values, keep .env out of git"):format(lang.label, table.concat(made, ", "))
    )
    if ex_created then
      vim.cmd.edit(vim.fn.fnameescape(ex_path))
    elseif env_path then
      vim.cmd.edit(vim.fn.fnameescape(env_path))
    end
  else
    log.info "Env: .env and .env.example already exist, opened them"
    local p = (vim.uv.fs_stat(root .. "/.env.example") and (root .. "/.env.example")) or (root .. "/.env")
    vim.cmd.edit(vim.fn.fnameescape(p))
  end
end

---@ Creates the .env files: picks the language when the project is ambiguous or has none
function M.create()
  local root = M.root()
  local cands = M.candidates(root)
  local detected = detect.detected(root)
  if #detected == 1 then
    return M.create_for(root, detected[1])
  end
  if #detected == 0 then
    -- no marker: let the user pick the stack (identical UI for every case)
    local items = vim.tbl_map(function(l)
      return { label = l.label, desc = l.id .. " preset", value = l }
    end, cands)
    return require("tasks.picker").choose(items, {
      title = "Env: choose the stack for " .. vim.fn.fnamemodify(root, ":~"),
      hint = "Enter choose · Esc cancel",
    }, function(l)
      M.create_for(root, l)
    end)
  end
  -- several: pick the primary stack
  local items = vim.tbl_map(function(l)
    return { label = l.label, desc = l.id .. " · detected", value = l }
  end, cands)
  require("tasks.picker").choose(items, {
    title = "Env: choose the stack for " .. vim.fn.fnamemodify(root, ":~"),
    hint = "Enter choose · Esc cancel",
  }, function(l)
    M.create_for(root, l)
  end)
end

---@ Creates .env.<name> from .env.example (APP_ENV set, never overwrites)
---@param env_name string e.g. "dev"
function M.create_named(env_name)
  local root = M.root()
  env_name = vim.trim(env_name or "")
  if env_name == "" then
    return log.warn "Env: empty environment name"
  end
  env_name = env_name:gsub("[^%w_%-]+", "_"):lower()
  local ex_text = require("utils.project").read(root .. "/.env.example")
  if not ex_text then
    -- no example yet: create one first for the detected stack, then copy
    M.create()
    vim.schedule(function()
      M.create_named(env_name)
    end)
    return
  end
  local body = ex_text:gsub("%s*$", "")
  -- set APP_ENV= if present, else prepend it
  if body:match "APP_ENV%s*=" then
    body = (body:gsub("APP_ENV%s*=.-\n", "APP_ENV=" .. env_name .. "\n", 1))
  else
    body = "APP_ENV=" .. env_name .. "\n" .. body
  end
  local path, created = write_file(root, ".env." .. env_name, body)
  M.ensure_gitignore(root)
  if created then
    log.info(("Env: created .env.%s from .env.example (APP_ENV=%s)"):format(env_name, env_name))
    vim.cmd.edit(vim.fn.fnameescape(path))
  else
    log.info(("Env: .env.%s already exists, opened it"):format(env_name))
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
end

---@ Asks for an environment name, then creates .env.<name>
function M.new_env()
  local modal = require "utils.modal"
  modal.input({
    { { "New environment", modal.hl.file } },
    { { "Creates .env.<name> from .env.example (APP_ENV set).", modal.hl.muted } },
    "",
    { { "Examples: dev, qa, staging, prod, test, local…", modal.hl.muted } },
  }, { title = "Env: new environment", confirm = "Create" }, function(text)
    if vim.trim(text) ~= "" then
      M.create_named(text)
    end
  end)
end

-- ── check ──────────────────────────────────────────────────────────────────

---@ Compares every .env* with .env.example and reports honestly
function M.check()
  local root = M.root()
  local ex_text = require("utils.project").read(root .. "/.env.example")
  if not ex_text then
    return log.warn "Env check: .env.example is missing — create it first (<leader>En)"
  end
  local ex_entries = parse.parse(ex_text)
  if #ex_entries == 0 then
    return log.warn "Env check: .env.example has no keys"
  end
  local files = parse.list_files(root)
  local lines = {}
  local problems = 0
  for _, path in ipairs(files) do
    if vim.fs.basename(path) ~= ".env.example" then
      local text = require("utils.project").read(path) or ""
      local entries = parse.parse(text)
      local d = parse.diff(ex_entries, entries)
      local name = vim.fs.basename(path)
      if #d.missing == 0 and #d.extra == 0 and #d.empty == 0 then
        lines[#lines + 1] = { { "  " .. name .. ": ok", require("utils.modal").hl.mark } }
      else
        problems = problems + 1
        lines[#lines + 1] = { { "  " .. name, require("utils.modal").hl.warn } }
        for _, k in ipairs(d.missing) do
          lines[#lines + 1] = { { "    missing " .. k, require("utils.modal").hl.warn } }
        end
        for _, k in ipairs(d.extra) do
          lines[#lines + 1] = { { "    extra   " .. k, require("utils.modal").hl.muted } }
        end
        for _, k in ipairs(d.empty) do
          lines[#lines + 1] = { { "    empty   " .. k, require("utils.modal").hl.muted } }
        end
      end
    end
  end
  local modal = require "utils.modal"
  local intro = {
    { { vim.fn.fnamemodify(root, ":~") .. "/.env.example", modal.hl.folder } },
    { { ("%d key(s) required"):format(#ex_entries), modal.hl.muted } },
    "",
  }
  local all =
    vim.list_extend(intro, #lines > 0 and lines or { { { "  no .env files yet — run <leader>En", modal.hl.muted } } })
  all[#all + 1] = ""
  all[#all + 1] = problems == 0 and { { "✓ all environments match .env.example", modal.hl.mark } }
    or { { ("%d file(s) need attention"):format(problems), modal.hl.warn } }
  modal.confirm(all, { title = "Env check", confirm = "Close", cancel = "Close" }, function() end)
  if problems > 0 then
    log.warn(("Env check: %d file(s) need attention — missing/extra/empty above"):format(problems))
  else
    log.info "Env check: all environments match .env.example"
  end
end

-- ── open ───────────────────────────────────────────────────────────────────

---@ Opens a specific env file by relative name (e.g. ".env", ".env.example", ".env.dev")
---@param rel string
function M.open_rel(rel)
  local root = M.root()
  local path = root .. "/" .. rel
  if vim.uv.fs_stat(path) == nil then
    return log.warn(("Env: %s does not exist — create it first (<leader>En)"):format(rel))
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

---@ Picker over the .env* files that exist (plus the ones the example promises)
function M.open_picker()
  local root = M.root()
  local files = parse.list_files(root)
  if #files == 0 then
    return log.warn "Env: no .env files yet — create them with <leader>En"
  end
  local items = vim.tbl_map(function(p)
    return { label = vim.fs.basename(p), desc = p:sub(#root + 2), path = p, value = p }
  end, files)
  require("tasks.picker").choose(items, {
    title = "Env files · " .. vim.fn.fnamemodify(root, ":~"),
    preview = true,
    hint = "Enter open · Esc cancel",
  }, function(p)
    vim.cmd.edit(vim.fn.fnameescape(p))
  end)
end

-- ── AI loader ──────────────────────────────────────────────────────────────

---@ AI generates the typed loader (identical UI in every language)
function M.ai()
  local root = M.root()
  local detected = detect.detected(root)
  local lang = detected[1]
  if not lang then
    local cands = M.candidates(root)
    local items = vim.tbl_map(function(l)
      return { label = l.label, desc = l.id .. " loader", value = l }
    end, cands)
    return require("tasks.picker").choose(items, {
      title = "Env AI: choose the language for the loader",
      hint = "Enter choose · Esc cancel",
    }, function(l)
      require("env.ai").generate(root, l)
    end)
  end
  if #detected > 1 then
    local items = vim.tbl_map(function(l)
      return { label = l.label, desc = l.id .. " · detected", value = l }
    end, detected)
    return require("tasks.picker").choose(items, {
      title = "Env AI: choose the language for the loader",
      hint = "Enter choose · Esc cancel",
    }, function(l)
      require("env.ai").generate(root, l)
    end)
  end
  require("env.ai").generate(root, lang)
end

-- ── menus ──────────────────────────────────────────────────────────────────

---@ The <leader>E maps (same shape for every language and every repo state)
---@return table[]
function M.maps()
  return {
    {
      "n",
      "create .env + .env.example",
      function()
        M.create()
      end,
    },
    {
      "e",
      "open .env",
      function()
        M.open_rel ".env"
      end,
    },
    {
      "x",
      "open .env.example",
      function()
        M.open_rel ".env.example"
      end,
    },
    {
      "l",
      "open .env.local",
      function()
        M.open_rel ".env.local"
      end,
    },
    {
      "d",
      "open .env.dev",
      function()
        M.open_rel ".env.dev"
      end,
    },
    {
      "q",
      "open .env.qa",
      function()
        M.open_rel ".env.qa"
      end,
    },
    {
      "s",
      "open .env.staging",
      function()
        M.open_rel ".env.staging"
      end,
    },
    {
      "p",
      "open .env.prod",
      function()
        M.open_rel ".env.prod"
      end,
    },
    {
      "c",
      "check .env files",
      function()
        M.check()
      end,
    },
    {
      "a",
      "AI generate env loader",
      function()
        M.ai()
      end,
    },
    {
      "o",
      "open env files",
      function()
        M.open_picker()
      end,
    },
    {
      "N",
      "new environment",
      function()
        M.new_env()
      end,
    },
    {
      "i",
      "ensure .gitignore",
      function()
        M.ensure_gitignore(M.root())
        log.info "Env: .gitignore has the secrets rules"
      end,
    },
  }
end

return M
