-- ── Language registry ────────────────────────────────────────────────────────
-- A language = a file in lua/languages/<name>.lua that DECLARES (does not
-- execute) what it needs. This module aggregates those declarations and exposes them
-- to each consumer (treesitter, mason, lsp, conform, nvim-lint, menus), so
-- that adding a language never forces editing another file (open/closed).
--
-- Contract of a language (all fields are optional):
--   filetypes   string[]            filetypes it covers (for menus and plugins)
--   treesitter  string[]            nvim-treesitter parsers
--   lsp         string[]            servers (lua/servers/<n>.lua = overrides)
--   mason       { always?, full? }  packages; `always` also in light mode
--   formatters  table<ft, string[]> conform
--   linters     table<ft, string[]> nvim-lint
--   linters_light table<ft, string[]> replaces `linters` in light mode
--   setup_lint  fun(lint)           registers custom linters
--   menu        { name, prefix, maps = {{key, desc, fn}...} }  leader menu
local settings = require "core.settings"
local light = require("core.light").enabled

local M = {}

-- Load order. To add a language: create its file and add it here.
local NAMES = {
  "lua",
  "go",
  "typescript",
  "html",
  "css",
  "tailwind",
  "json",
  "yaml",
  "toml",
  "markdown",
  "docker",
  "prisma",
  "astro",
  "dart",
  "rust",
  "python",
  "java",
  "kotlin",
  "yarnspinner",
}

---@type table[]?
local cache

---@return table[]
local function all()
  if cache then
    return cache
  end
  cache = {}
  for _, name in ipairs(NAMES) do
    if not vim.tbl_contains(settings.languages.disabled, name) then
      local spec = require("languages." .. name)
      spec.name = spec.name or name
      table.insert(cache, spec)
    end
  end
  return cache
end

---@param list string[]
---@return string[]
local function unique(list)
  local seen, out = {}, {}
  for _, item in ipairs(list) do
    if not seen[item] then
      seen[item] = true
      table.insert(out, item)
    end
  end
  return out
end

---@param field string
---@return string[]
local function collect(field)
  local out = {}
  for _, lang in ipairs(all()) do
    vim.list_extend(out, lang[field] or {})
  end
  return unique(out)
end

---@return table[]
function M.list()
  return all()
end

---@return string[]
function M.treesitter()
  return collect "treesitter"
end

--- LSP servers to enable (none in light mode)
---@return string[]
function M.lsp_servers()
  if light then
    return {}
  end
  return collect "lsp"
end

--- Mason packages (only `always` in light mode)
---@return string[]
function M.mason()
  local out = {}
  for _, lang in ipairs(all()) do
    local mason = lang.mason or {}
    vim.list_extend(out, mason.always or {})
    if not light then
      vim.list_extend(out, mason.full or {})
    end
  end
  return unique(out)
end

--- Merges the ft -> tools maps of all languages
---@param fields string[] fields in increasing order of precedence
---@return table<string, string[]>
local function merge_by_filetype(fields)
  local out = {}
  for _, lang in ipairs(all()) do
    for _, field in ipairs(fields) do
      for ft, tools in pairs(lang[field] or {}) do
        out[ft] = tools
      end
    end
  end
  return out
end

---@return table<string, string[]>
function M.formatters()
  return merge_by_filetype { "formatters" }
end

--- In light mode `linters_light` replaces `linters` only for the fts it defines
---@return table<string, string[]>
function M.linters()
  return merge_by_filetype(light and { "linters", "linters_light" } or { "linters" })
end

--- Registers the custom linters of each language
---@param lint table nvim-lint module
function M.setup_lint(lint)
  for _, lang in ipairs(all()) do
    if lang.setup_lint then
      lang.setup_lint(lint)
    end
  end
end

--- Menu contexts (one menu per language that declares it)
---@return table[]
function M.menus()
  local out = {}
  for _, lang in ipairs(all()) do
    if lang.menu then
      table.insert(out, vim.tbl_extend("keep", { filetypes = lang.filetypes }, lang.menu))
    end
  end
  return out
end

return M
