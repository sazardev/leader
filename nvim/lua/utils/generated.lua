-- ── Generated files ──────────────────────────────────────────────────────────
-- Code a generator writes (build_runner, protobuf): it is rewritten on the next build, so nothing should edit it and
-- searches and the agent's context should not read it (a freezed class is ~5x longer in its `.freezed.dart` than in its
-- source). One list for everyone: the agent's types, code search, the architecture levels' searches.
local M = {}

--- File names, as globs (ripgrep) and the Lua patterns that match them
M.GLOBS = {
  "*.g.dart",
  "*.freezed.dart",
  "*.gr.dart",
  "*.mocks.dart",
  "*.pb.dart",
  "*.pbenum.dart",
  "*.pbgrpc.dart",
  "*.pbjson.dart",
  "*.pb.go",
  "*.pb.gw.go",
  "*_grpc.pb.go",
}

local PATTERNS = vim.tbl_map(function(glob)
  return glob:gsub("%.", "%%."):gsub("^%*", "") .. "$"
end, M.GLOBS)

--- Is this file written by a generator?
---@param path string
---@return boolean
function M.is_generated(path)
  local name = path:match "[^/\\]+$" or path
  for _, pattern in ipairs(PATTERNS) do
    if name:find(pattern) then
      return true
    end
  end
  return false
end

--- ripgrep arguments that leave them out
---@return string[]
function M.rg_excludes()
  local args = {}
  for _, glob in ipairs(M.GLOBS) do
    vim.list_extend(args, { "--glob", "!" .. glob })
  end
  return args
end

return M
