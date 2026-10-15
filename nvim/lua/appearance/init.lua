-- ── Appearance: default theme vs. theme inherited from the terminal ──────────
-- "default" = settings.theme.name (gruvbox). "terminal" = Alacritty palette
-- converted to a base46 theme (see terminal_theme.lua). Any chosen theme
-- (also from the NvChad picker) is remembered across sessions.
local alacritty = require "appearance.alacritty"
local log = require "utils.log"
local settings = require "core.settings"
local state = require "appearance.state"
local watcher = require "appearance.watcher"

local M = {}

M.TERMINAL = "terminal"

-- Signature of the Alacritty files THIS instance's highlights were built from. The compiled marker on disk is shared
-- by every open Neovim (it lives next to the shared base46 cache): the first instance that sees a change recompiles
-- and updates it, so the others must compare against what they applied themselves, or they would never repaint.
---@type string?
local applied

local function terminal_enabled()
  return settings.theme.terminal.enabled
end

---@return string
function M.default()
  return settings.theme.name
end

---@return string theme active right now
function M.current()
  return require("nvconfig").base46.theme
end

--- Theme Neovim starts with: the last chosen one, or the default if the terminal
--- theme is no longer available (no Alacritty config, disabled...).
---@return string
function M.initial()
  local saved = state.read_choice().theme
  if saved == M.TERMINAL then
    if not terminal_enabled() then
      return M.default()
    end
    -- the compiled cache already is this config, untouched: no need to look for it or parse it
    local compiled = state.read_compiled()
    if compiled.theme == M.TERMINAL and compiled.signature and alacritty.unchanged(compiled.signature) then
      return M.TERMINAL
    end
    return alacritty.load() and M.TERMINAL or M.default()
  end
  return saved or M.default()
end

--- Follows the Alacritty config live, but only while the active theme is the
--- terminal one (with the default no polling is running).
function M.watch()
  if M.current() ~= M.TERMINAL or not terminal_enabled() then
    return watcher.stop()
  end
  watcher.start(function()
    if M.refresh() then
      log.info "Terminal theme updated"
    end
  end)
end

--- Remembers the current theme: the user's choice and what ended up compiled.
--- The signature is the one from the CACHED read (the one the compilation used), never a
--- re-read: if the file changed during compilation, the saved signature
--- stays stale and the polling recompiles (with a re-read that change would be lost).
function M.persist()
  local name = M.current()
  local loaded = name == M.TERMINAL and alacritty.load() or nil
  state.write_choice(name)
  applied = loaded and loaded.signature or nil
  -- the palette goes with its signature: the next start reads it from here instead of searching and parsing the config
  state.write_compiled {
    theme = name,
    signature = applied,
    palette = loaded and loaded.palette or nil,
    config = loaded and loaded.config or nil,
    theme_file = loaded and loaded.theme_file or nil,
  }
  M.watch()
end

--- Applies a theme: recompiles the base46 highlights on the fly
---@param name string
---@return boolean ok
function M.use(name)
  if name == M.TERMINAL then
    alacritty.reset()
    local loaded, err = alacritty.load()
    if not terminal_enabled() then
      log.warn "Terminal theme is disabled (settings.theme.terminal.enabled)"
      return false
    elseif not loaded then
      log.warn(err or "Could not read the terminal palette")
      return false
    end
  end

  package.loaded["themes.terminal"] = nil -- re-read the palette
  require("nvconfig").base46.theme = name
  require("base46").load_all_highlights()
  M.persist()
  return true
end

--- Toggles between the default theme and the one inherited from the terminal
function M.toggle()
  local target = M.current() == M.TERMINAL and M.default() or M.TERMINAL
  if M.use(target) then
    log.info("Theme: " .. target)
  end
end

--- Ensures the highlight cache matches the desired theme (and, if it is the
--- terminal one, the current Alacritty config); otherwise recompiles. Cheap: it only
--- compares the cache marker with the signature (mtime + size) of the files.
---@return boolean changed
function M.sync()
  local desired = M.initial()
  local compiled = state.read_compiled()
  -- the usual start: the cache was compiled from these very files. Only `stat` (a full read costs ~60 ms on WSL)
  if
    desired == M.TERMINAL
    and compiled.theme == M.TERMINAL
    and compiled.signature
    and alacritty.unchanged(compiled.signature)
  then
    applied = compiled.signature
    alacritty.prime(compiled.signature)
    return false
  end
  local signature = desired == M.TERMINAL and alacritty.signature() or nil
  if compiled.theme == desired and compiled.signature == signature then
    applied = signature
    return false
  end
  return M.use(desired)
end

--- While the terminal theme is active: repaints THIS instance when the Alacritty palette differs from the one its
--- highlights came from (another instance may already have recompiled the shared cache and its marker).
---@return boolean changed
function M.refresh()
  if M.current() ~= M.TERMINAL or not terminal_enabled() then
    return false
  end
  if applied and alacritty.unchanged(applied) then
    return false -- nothing changed (FocusGained calls this every time): no search, no parse
  end
  local signature = alacritty.signature()
  if not signature or signature == applied then
    return false
  end
  return M.use(M.TERMINAL)
end

--- Source of the current theme and live-tracking state, on a single line
--- (several lines trigger "Press ENTER" and swallow the following keys)
---@return string
function M.info()
  local name = M.current()
  local loaded = name == M.TERMINAL and alacritty.load() or nil
  if loaded then
    local p = loaded.palette
    local live = watcher.active() and ("live every %d ms"):format(settings.theme.terminal.watch_ms) or "NOT watching"
    return ("Theme: terminal · %s · background %s · %d watched files · %s"):format(
      vim.fs.basename(loaded.theme_file or loaded.config),
      p.background,
      #loaded.files,
      live
    )
  end
  local detected = alacritty.find_config() and "Alacritty detected" or "no Alacritty config"
  return ("Theme: %s · %s"):format(name, detected)
end

return M
