-- ── What the project looks like ──────────────────────────────────────────────
-- `scan` lists the names found in the project (a few levels deep, never inside dependency or build folders), `match` and
-- `run` are pure: they take those names and say which presets apply and why. Nothing is read from the files' content.
local M = {}

--- Folders whose own name counts (`node_modules/` says Node) but whose content is not walked
M.SKIP = {
  [".git"] = true,
  ["node_modules"] = true,
  ["vendor"] = true,
  ["target"] = true,
  ["build"] = true,
  ["dist"] = true,
  [".venv"] = true,
  ["venv"] = true,
  ["__pycache__"] = true,
  [".dart_tool"] = true,
  [".gradle"] = true,
  ["Pods"] = true,
  [".next"] = true,
  [".terraform"] = true,
}

--- The names under `root`: files as they are, folders with a trailing slash
---@param root string
---@param opts { depth: integer?, max: integer? }?
---@return string[]
function M.scan(root, opts)
  opts = opts or {}
  local out = {}
  local max = opts.max or 4000
  local ok, iter = pcall(vim.fs.dir, root, {
    depth = opts.depth or 3,
    skip = function(name)
      return not M.SKIP[name]
    end,
  })
  if not ok then
    return out
  end
  for path, kind in iter do
    local name = vim.fs.basename(path)
    if kind == "directory" then
      name = name .. "/"
    end
    out[#out + 1] = name
    if #out >= max then
      break
    end
  end
  return out
end

--- Does a `detect` token match a name? `go.mod` exactly, `*.go` / `.env.*` as a glob on the whole name, `node_modules/`
--- for a folder (names carry the slash)
---@param token string
---@param name string
---@return boolean
function M.match(token, name)
  if not token:find("*", 1, true) then
    return token == name
  end
  local lua = "^" .. token:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  return name:match(lua) ~= nil
end

---@class IgnoreHit
---@field first string   the first name that matched
---@field count integer  how many matched
---@field always boolean

--- Which presets apply: name → what matched. `always` presets are in even when nothing matched
---@param presets IgnorePreset[]
---@param names string[]
---@return table<string, IgnoreHit>
function M.run(presets, names)
  local out = {}
  for _, preset in ipairs(presets) do
    local hit
    for _, token in ipairs(preset.detect) do
      if token == "always" then
        hit = hit or { count = 0 }
        hit.always = true
      else
        for _, name in ipairs(names) do
          if M.match(token, name) then
            hit = hit or { count = 0 }
            hit.first = hit.first or name
            hit.count = hit.count + 1
          end
        end
      end
    end
    if hit then
      hit.always = hit.always or false
      hit.first = hit.first or ""
      out[preset.name] = hit
    end
  end
  return out
end

return M
