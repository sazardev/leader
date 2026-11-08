-- ── Env: language detection ────────────────────────────────────────────────
-- Reads the project markers under the git root (one stat per language, no recursion) and returns the matching
-- presets in `init.lua` order. Pure except for the fs check, so it stays cheap to call from a menu.
local M = {}

---@ The languages the env presets know, in picker order
M.IDS = { "go", "typescript", "python", "rust", "csharp", "swift", "dart", "jvm", "generic" }

---@ Load a language preset module (nil when the file is missing)
---@param id string
---@return table?
function M.lang(id)
  local ok, mod = pcall(require, "env.langs." .. id)
  return ok and type(mod) == "table" and mod or nil
end

---@ Every preset that matches the markers under `root`
---@param root string
---@return table[]
function M.detected(root)
  local out = {}
  if not root or vim.uv.fs_stat(root) == nil then
    return out
  end
  for _, id in ipairs(M.IDS) do
    local l = M.lang(id)
    if l and id ~= "generic" then
      local hit = false
      for _, m in ipairs(l.markers or {}) do
        -- markers may be a plain name ("go.mod") or a pattern ("*.csproj", "*.sln")
        if m:match "%*" then
          local pat = "^" .. vim.pesc(m):gsub("\\%*", ".*") .. "$"
          local iter = vim.fs.dir(root)
          if iter then
            for name, kind in vim.fs.dir(root) do
              if kind == "file" and name:match(pat) then
                hit = true
                break
              end
            end
          end
        else
          if vim.uv.fs_stat(root .. "/" .. m) ~= nil then
            hit = true
          end
        end
        if hit then
          break
        end
      end
      if hit then
        out[#out + 1] = l
      end
    end
  end
  return out
end

---@ The best preset for a root: the first detected one, else `generic`
---@param root string
---@return table
function M.primary(root)
  local d = M.detected(root)
  if d[1] then
    return d[1]
  end
  return M.lang "generic"
    or {
      id = "generic",
      label = "Generic",
      vars = function()
        return {}
      end,
      template = function()
        return ""
      end,
    }
end

return M
