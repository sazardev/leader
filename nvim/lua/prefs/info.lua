-- ── Settings: info panel ─────────────────────────────────────────────────────
-- What is running right now, in one reading panel (version, startup, theme, light mode, language servers, paths). Pure
-- `lines(facts)` so the text is tested; `facts()` is the only part that looks at the editor.
local M = {}

---@class PrefsFacts
---@field version string
---@field root string?        the config's repository (nil if it is not a clone)
---@field startup_ms number?
---@field plugins { loaded: integer, count: integer }?
---@field theme string
---@field light boolean
---@field servers string[]
---@field saved integer        choices saved from the settings panel

---@param facts PrefsFacts
---@return string[]
function M.lines(facts)
  local function row(label, value)
    return ("- **%s** %s"):format(label, value)
  end
  local lines = { "# Info", "" }
  lines[#lines + 1] = row("Config", facts.version .. (facts.root and (" · " .. facts.root) or ""))
  if facts.startup_ms then
    local plugins = facts.plugins and (" · %d of %d plugins loaded"):format(facts.plugins.loaded, facts.plugins.count)
      or ""
    lines[#lines + 1] = row("Startup", ("%.0f ms%s"):format(facts.startup_ms, plugins))
  end
  lines[#lines + 1] = row("Theme", facts.theme)
  lines[#lines + 1] = row("Light mode", facts.light and "on (no resident language servers)" or "off")
  lines[#lines + 1] =
    row("Language servers", #facts.servers > 0 and table.concat(facts.servers, ", ") or "none in this buffer")
  lines[#lines + 1] =
    row("Saved choices", facts.saved == 0 and "none" or ("%d from the settings panel"):format(facts.saved))
  return lines
end

---@return PrefsFacts
function M.facts()
  local config = vim.uv.fs_realpath(vim.fn.stdpath "config") or vim.fn.stdpath "config"
  local root = vim.fs.dirname(config)
  local version = "unknown"
  local f = io.open(root .. "/VERSION", "r")
  if f then
    version = "v" .. vim.trim(f:read "*a")
    f:close()
  end
  local ok, stats = pcall(function()
    return require("lazy").stats()
  end)
  local names, seen = {}, {}
  for _, client in ipairs(vim.lsp.get_clients { bufnr = 0 }) do
    if not seen[client.name] then
      seen[client.name] = true
      names[#names + 1] = client.name
    end
  end
  local saved = 0
  for _ in pairs(require("prefs.store").read()) do
    saved = saved + 1
  end
  return {
    version = version,
    root = vim.uv.fs_stat(root .. "/.git") and root or nil,
    startup_ms = ok and stats.startuptime or nil,
    plugins = ok and { loaded = stats.loaded, count = stats.count } or nil,
    theme = require("appearance").current(),
    light = require("core.light").enabled,
    servers = names,
    saved = saved,
  }
end

function M.open()
  require("agent.ui.panel").open(
    M.lines(M.facts()),
    "Info",
    { hint = "BS back · q close", on_back = require("prefs").open }
  )
end

return M
