-- ── Reading the Alacritty config ─────────────────────────────────────────────
-- Locates alacritty.toml, resolves its `import`s with Alacritty's rules
-- (imports are applied in order; the importing file overrides its imports)
-- and returns the resulting color palette.
local toml = require "appearance.toml"

local M = {}

local MAX_IMPORT_DEPTH = 5

local NAMES = { "normal", "bright" }
local ANSI = { "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }

--- Alacritty default colors when the config does not define `[colors]`
local DEFAULTS = {
  background = "#181818",
  foreground = "#d8d8d8",
  normal = { "#181818", "#ac4242", "#90a959", "#f4bf75", "#6a9fb5", "#aa759f", "#75b5aa", "#d8d8d8" },
  bright = { "#6b6b6b", "#c55555", "#aac474", "#feca88", "#82b8c8", "#c28cb8", "#93d3c3", "#f8f8f8" },
}

--- Modification stamp of a file (mtime + size); "" if it does not exist
---@param path string
---@return string
local function stamp(path)
  local stat = vim.uv.fs_stat(path)
  return stat and ("%d.%d:%d"):format(stat.mtime.sec, stat.mtime.nsec, stat.size) or ""
end

---@param path string
---@return string
local function expand(path)
  return vim.fs.normalize(path)
end

--- Candidates in priority order: user override, Linux/macOS, Windows and
--- (on WSL) the most recently modified Windows AppData.
---@return string[]
local function candidates()
  local list = {}
  local override = require("core.settings").theme.terminal.config
  if override then
    table.insert(list, expand(override))
  end

  local xdg = vim.env.XDG_CONFIG_HOME or "~/.config"
  vim.list_extend(list, { expand(xdg .. "/alacritty/alacritty.toml"), expand "~/.alacritty.toml" })
  if vim.env.APPDATA then
    table.insert(list, expand(vim.env.APPDATA .. "/alacritty/alacritty.toml"))
  end

  -- WSL: Alacritty runs on Windows and its config lives in /mnt/<drive>/Users/*/AppData
  local wsl = vim.fn.glob("/mnt/*/Users/*/AppData/Roaming/alacritty/alacritty.toml", false, true)
  table.sort(wsl, function(a, b)
    local sa, sb = vim.uv.fs_stat(a), vim.uv.fs_stat(b)
    return (sa and sa.mtime.sec or 0) > (sb and sb.mtime.sec or 0)
  end)
  return vim.list_extend(list, wsl)
end

---@type string? the config found in this session: the search globs /mnt/*/Users/* (the Windows disk on WSL, ~20 ms)
local found

---@return string?
function M.find_config()
  if found and vim.uv.fs_stat(found) then
    return found
  end
  found = nil
  for _, path in ipairs(candidates()) do
    if vim.uv.fs_stat(path) then
      found = path
      return path
    end
  end
end

---@param value any
---@return string? "#rrggbb"
local function normalize(value)
  if type(value) ~= "string" then
    return nil
  end
  local hex = value:match "^#(%x%x%x%x%x%x)$" or value:match "^0x(%x%x%x%x%x%x)$"
  return hex and "#" .. hex:lower() or nil
end

---@param a table
---@param b table
---@return table b merged over a (b wins)
local function merge(a, b)
  return vim.tbl_deep_extend("force", a, b)
end

--- Reads a file and all its imports (recursive). Returns the merged table and
--- records every visited file and which one defined the background.
---@param path string
---@param ctx { files: table[], theme_file: string? }
---@param depth integer
---@return table
local function load_file(path, ctx, depth)
  -- The stamp is taken BEFORE reading: if the file changes between the two, the
  -- stamp ends up older than the content and the polling detects it as stale
  -- (the other way around the update would be lost).
  local file_stamp = stamp(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local text = f:read "*a"
  f:close()

  table.insert(ctx.files, { path = path, stamp = file_stamp })

  local own = toml.parse(text)
  local imports = (own.general and own.general.import) or own.import or {}

  local result = {}
  if depth < MAX_IMPORT_DEPTH then
    for _, rel in ipairs(type(imports) == "table" and imports or {}) do
      local target = expand(rel:sub(1, 1) == "~" and rel or (vim.fs.dirname(path) .. "/" .. rel))
      result = merge(result, load_file(target, ctx, depth + 1))
    end
  end

  if own.colors and own.colors.primary and own.colors.primary.background then
    ctx.theme_file = path
  end
  return merge(result, own)
end

---@param colors table merged [colors] section
---@return table palette
local function build_palette(colors)
  local primary = colors.primary or {}
  local palette = {
    background = normalize(primary.background) or DEFAULTS.background,
    foreground = normalize(primary.foreground) or DEFAULTS.foreground,
    selection = normalize((colors.selection or {}).background),
    cursor = normalize((colors.cursor or {}).cursor),
    ansi = {}, -- ansi[1..16] = black..white, bright black..bright white
  }
  for set_index, set in ipairs(NAMES) do
    for i, name in ipairs(ANSI) do
      palette.ansi[(set_index - 1) * 8 + i] = normalize((colors[set] or {})[name]) or DEFAULTS[set][i]
    end
  end
  return palette
end

---@type table?
local cache

--- Loads and caches the Alacritty palette
---@return { palette: table, config: string, theme_file: string?, signature: string }?, string? err
function M.load()
  if cache then
    return cache
  end
  -- the palette compiled last time, if its files are untouched: no search on /mnt/c, no TOML parsing (the usual start)
  local compiled = require("appearance.state").read_compiled()
  local override = require("core.settings").theme.terminal.config
  if
    compiled.palette
    and compiled.config
    and compiled.signature
    and (not override or expand(override) == compiled.config)
    and M.unchanged(compiled.signature)
  then
    cache = {
      palette = compiled.palette,
      config = compiled.config,
      theme_file = compiled.theme_file,
      files = M.files_of(compiled.signature),
      signature = compiled.signature,
    }
    return cache
  end
  local config = M.find_config()
  if not config then
    return nil, "Alacritty config not found (see theme.terminal.config in core/settings.lua)"
  end
  local ctx = { files = {} }
  local merged = load_file(config, ctx, 0)
  cache = {
    palette = build_palette(merged.colors or {}),
    config = config,
    theme_file = ctx.theme_file,
    files = ctx.files,
    signature = table.concat(
      vim.tbl_map(function(f)
        return f.path .. ":" .. f.stamp
      end, ctx.files),
      "|"
    ),
  }
  return cache
end

--- Signature of the files that define the palette (changes if any is edited)
---@return string?
function M.signature()
  M.reset()
  local loaded = M.load()
  return loaded and loaded.signature or nil
end

--- The files and stamps a signature recorded ("path:sec.nsec:size|…")
---@param signature string
---@return { path: string, stamp: string }[]
function M.files_of(signature)
  local files = {}
  for entry in signature:gmatch "[^|]+" do
    local path, recorded = entry:match "^(.*):(%-?%d+%.%d+:%d+)$"
    if not path then
      path, recorded = entry:match "^(.*):()$" -- a file that did not exist: empty stamp
      recorded = ""
    end
    if path then
      files[#files + 1] = { path = path, stamp = recorded }
    end
  end
  return files
end

--- Are the files of a signature exactly as recorded? Only `stat`s them: no search for the config, no parsing. This is
--- what keeps the terminal theme free at startup (the config lives on /mnt/c on WSL, where reading is slow).
---@type { signature: string, result: boolean, at: integer }? the last answer: startup asks several times in a row
local last_check

---@param signature string
---@return boolean
function M.unchanged(signature)
  local now = vim.uv.now()
  if last_check and last_check.signature == signature and now - last_check.at < 500 then
    return last_check.result
  end
  local result = M.check_files(signature)
  last_check = { signature = signature, result = result, at = now }
  return result
end

--- `unchanged` without the short memory (the watcher's poll must see every change)
---@param signature string
---@return boolean
function M.check_files(signature)
  local files = M.files_of(signature)
  if #files == 0 then
    return false
  end
  for _, f in ipairs(files) do
    if stamp(f.path) ~= f.stamp then
      return false
    end
  end
  return true
end

---@type { path: string, stamp: string }[]? files to watch when the palette was not loaded (it came from the cache)
local watched

--- Watch the files of a known signature without loading the palette
---@param signature string
function M.prime(signature)
  watched = M.files_of(signature)
end

--- Did any config file change since the last read? It only does `stat`
--- (no re-reading or parsing), so it is suitable for periodic polling.
---@return boolean
function M.is_stale()
  local files = cache and cache.files or watched
  if not files then
    return false
  end
  for _, file in ipairs(files) do
    if stamp(file.path) ~= file.stamp then
      return true
    end
  end
  return false
end

--- Discards the cache (re-read on the next load)
function M.reset()
  cache = nil
  last_check = nil
end

return M
