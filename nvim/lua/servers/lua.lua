-- ── Which language server Lua gets ───────────────────────────────────────────
-- lua_ls parses every file of the workspace and of its libraries before it can answer across files: ~3.8 s here for 670
-- files and it keeps nothing between sessions. emmylua_ls (the Rust one) answers across files in ~0.7 s on the same
-- workspace and works with lazydev. `settings.lsp.lua_server` = "auto" uses emmylua_ls when it is installed (Mason
-- installs it with the rest) and lua_ls otherwise; naming one forces it, but Lua never ends up with no server.
local M = {}

M.SERVERS = { "emmylua_ls", "lua_ls" }

--- Pure: the server to use
---@param pref string? "auto" | "emmylua_ls" | "lua_ls"
---@param installed table<string, boolean> which of the two are available
---@return string
function M.choose(pref, installed)
  if pref == "lua_ls" then
    return "lua_ls"
  end
  if installed.emmylua_ls then
    return "emmylua_ls"
  end
  return "lua_ls" -- not installed (yet): the one that always worked
end

--- Is the emmylua_ls binary there? (Mason's bin may not be on PATH yet when the servers are set up)
---@return boolean
function M.has_emmylua()
  return vim.fn.executable "emmylua_ls" == 1 or vim.uv.fs_stat(vim.fn.stdpath "data" .. "/mason/bin/emmylua_ls") ~= nil
end

---@return string
function M.pick()
  local pref = (require("core.settings").lsp or {}).lua_server
  return M.choose(pref, { emmylua_ls = M.has_emmylua(), lua_ls = true })
end

return M
