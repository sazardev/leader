-- ── DDD layers: what each directory is and who may depend on whom ────────────
local settings = require("core.settings").agent.ddd

local M = {}

--- The dependency rule: each layer can only point inward
M.ALLOWED = {
  domain = { domain = true },
  application = { domain = true, application = true },
  infrastructure = { domain = true, application = true, infrastructure = true },
  interface = { domain = true, application = true, interface = true },
}

M.ORDER = { "domain", "application", "infrastructure", "interface" }

---@type table<string, string>?
local lookup

---@return table<string, string> segment → layer
local function segments()
  if not lookup then
    lookup = {}
    for layer, names in pairs(settings.layers) do
      for _, name in ipairs(names) do
        lookup[name:lower()] = layer
      end
    end
  end
  return lookup
end

--- The layer of a path or an import: the FIRST segment (left to right) that is a layer name
---@param path string
---@return string?
function M.of(path)
  local map = segments()
  for seg in path:gmatch "[^/\\%.:]+" do
    local layer = map[seg:lower()]
    if layer then
      return layer
    end
  end
  return nil
end

--- Is the file a composition root (main, cmd/, container...), which may wire all layers?
---@param rel string path relative to the project root
---@return boolean
function M.is_composition_root(rel)
  local lower = rel:lower()
  for _, root in ipairs(settings.composition_roots) do
    if
      lower:find("^" .. root .. "[/%.]")
      or lower:find("/" .. root .. "[/%.]")
      or lower:match("[/^]" .. root .. "$")
    then
      return true
    end
  end
  return false
end

--- Directories and files that do not count for the rules
---@param rel string
---@return boolean
function M.is_test(rel)
  local lower = rel:lower()
  return lower:find "_test%." ~= nil
    or lower:find "%.test%." ~= nil
    or lower:find "%.spec%." ~= nil
    or lower:find "/tests?/" ~= nil
    or lower:find "^tests?/" ~= nil
    or lower:find "/__tests__/" ~= nil
    or lower:find "/mocks?/" ~= nil
    or lower:find "^test_" ~= nil
    or lower:find "/test_" ~= nil
end

--- Resets the names cache (settings.agent.ddd.layers changed)
function M.reset()
  lookup = nil
end

return M
