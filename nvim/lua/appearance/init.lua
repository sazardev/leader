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
    return (terminal_enabled() and alacritty.load()) and M.TERMINAL or M.default()
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
    if M.sync() then
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
  state.write_compiled { theme = name, signature = loaded and loaded.signature or nil }
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
  local signature = desired == M.TERMINAL and alacritty.signature() or nil
  if compiled.theme == desired and compiled.signature == signature then
    return false
  end
  return M.use(desired)
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
