-- Writes the per-machine settings (nvim/lua/local.lua, git-ignored) requested by the installer options. Used by
-- install.sh and install.ps1 (a single implementation, without loading the config or the plugins):
--   nvim -u NONE --headless -l scripts/install-local.lua
-- Input (environment variables, all optional):
--   NVIM_INSTALL_LANGS   "python,sql"     keeps only those packs or languages (+ the base); the rest go to
--                                        `languages.disabled` (packs: nvim/lua/languages/packs.lua; "all" keeps every one)
--   NVIM_INSTALL_THEME   "catppuccin"     `theme.name`
--   NVIM_INSTALL_LIGHT   "1" | "0"        `light.force` (light mode forced on / off)
--   NVIM_INSTALL_LOCAL   path             where to write (default nvim/lua/local.lua; used by the tests)
--   NVIM_INSTALL_DRY     "1"              shows what it would write without writing
-- Output: one line per message, prefixed `OK `, `WARN ` or `ERR ` (the installer colors them); exits with 2 on an ERR.
-- Two helpers for the installers' language checklist, so the packs are written down once:
--   … -l scripts/install-local.lua --packs          one pack per line: id<TAB>label<TAB>detect commands<TAB>languages
--   … -l scripts/install-local.lua --expand go,web  the languages a choice keeps, comma-separated
-- If local.lua already exists it is NOT touched: it says what to add (it is yours, it may have other settings).
local M = {}

local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

--- Language names from the registry (without loading it: its `NAMES` list is read)
---@param root string
---@return string[]
function M.language_names(root)
  local ok, lines = pcall(vim.fn.readfile, root .. "/nvim/lua/languages/init.lua")
  local names, inside = {}, false
  for _, line in ipairs(ok and lines or {}) do
    if line:match "^local NAMES = {" then
      inside = true
    elseif inside and line:match "^}" then
      break
    elseif inside then
      local name = line:match '"([%w_]+)"'
      if name then
        names[#names + 1] = name
      end
    end
  end
  return names
end

---@param value any
---@return string
local function lua_value(value)
  if type(value) == "table" then
    if vim.islist(value) then
      return "{ " .. table.concat(vim.tbl_map(lua_value, value), ", ") .. " }"
    end
    local keys = vim.tbl_keys(value)
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = ("%s = %s"):format(k, lua_value(value[k]))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  return type(value) == "string" and ("%q"):format(value) or tostring(value)
end

--- The language packs (nvim/lua/languages/packs.lua)
---@param root string
---@return { base: string[], packs: { id: string, label: string, langs: string[], detect: string[] }[] }
function M.packs(root)
  local ok, packs = pcall(dofile, root .. "/nvim/lua/languages/packs.lua")
  return ok and type(packs) == "table" and packs or { base = { "lua" }, packs = {} }
end

--- The languages a choice keeps (pure): the base, then each pack id or language name of `text`; "all" keeps all
---@param text string "python,sql" | "go,typescript" | "all"
---@param names string[] every registry language
---@param packs table
---@return table<string, boolean>? keep, string? err
function M.expand(text, names, packs)
  local keep = {}
  for _, n in ipairs(packs.base or { "lua" }) do
    keep[n] = true
  end
  keep.lua = true
  local by = {}
  for _, p in ipairs(packs.packs or {}) do
    by[p.id] = p
  end
  for token in text:gmatch "[^,%s]+" do
    if token == "all" then
      for _, n in ipairs(names) do
        keep[n] = true
      end
    elseif by[token] then
      for _, n in ipairs(by[token].langs) do
        keep[n] = true
      end
    elseif vim.tbl_contains(names, token) then
      keep[token] = true
    elseif token ~= "none" and token ~= "base" then
      local ids = vim.tbl_map(function(p)
        return p.id
      end, packs.packs or {})
      return nil, ("unknown language: %s (packs: %s; languages: %s)"):format(token, table.concat(ids, " "), table.concat(names, " "))
    end
  end
  return keep
end

---@param env { langs: string?, theme: string?, light: string? }
---@param names string[]
---@param packs table? default: the repo's packs
---@return table? settings, string? err
function M.plan(env, names, packs)
  local settings = {}
  if env.langs then
    local keep, err = M.expand(env.langs, names, packs or M.packs(ROOT))
    if not keep then
      return nil, err
    end
    settings.languages = {
      disabled = vim.tbl_filter(function(n)
        return not keep[n]
      end, names),
    }
  end
  if env.theme then
    settings.theme = { name = env.theme }
  end
  if env.light == "1" or env.light == "0" then
    settings.light = { force = env.light == "1" }
  end
  return settings
end

---@param settings table
---@return string
function M.render(settings)
  return "return " .. lua_value(settings)
end

---@param value string?
---@return string?
local function nonempty(value)
  return value and value ~= "" and value or nil
end

function M.main()
  local env = {
    langs = nonempty(os.getenv "NVIM_INSTALL_LANGS"),
    theme = nonempty(os.getenv "NVIM_INSTALL_THEME"),
    light = nonempty(os.getenv "NVIM_INSTALL_LIGHT"),
  }
  local path = nonempty(os.getenv "NVIM_INSTALL_LOCAL") or (ROOT .. "/nvim/lua/local.lua")
  local settings, err = M.plan(env, M.language_names(ROOT))
  if not settings then
    io.stdout:write("ERR ", err, "\n")
    os.exit(2)
  end
  if next(settings) == nil then
    return
  end
  local body = M.render(settings)
  local summary = body:gsub("^return ", "")
  if vim.uv.fs_stat(path) then
    io.stdout:write("WARN lua/local.lua already exists: add inside its table → ", summary:sub(3, -3), "\n")
  elseif os.getenv "NVIM_INSTALL_DRY" == "1" then
    io.stdout:write("OK [dry-run] would write lua/local.lua: ", body, "\n")
  else
    vim.fn.writefile({ "-- Generated by the installer (per-machine settings, git-ignored)", body }, path)
    io.stdout:write("OK lua/local.lua: ", summary, "\n")
  end
end

if not vim.g.install_local_test then
  local args = _G.arg or {}
  if args[1] == "--packs" then
    for _, p in ipairs(M.packs(ROOT).packs) do
      io.stdout:write(("%s\t%s\t%s\t%s\n"):format(p.id, p.label, table.concat(p.detect, " "), table.concat(p.langs, " ")))
    end
  elseif args[1] == "--expand" then
    local names = M.language_names(ROOT)
    local keep, err = M.expand(args[2] or "", names, M.packs(ROOT))
    if not keep then
      io.stdout:write("ERR ", err, "\n")
      os.exit(2)
    end
    io.stdout:write(table.concat(vim.tbl_filter(function(n)
      return keep[n]
    end, names), ","), "\n")
  else
    M.main()
  end
  vim.cmd "qa!"
end

return M
