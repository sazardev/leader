-- ── Language servers: stop, restart, pause ───────────────────────────────────
-- A server can take seconds (lua_ls) or much longer (gopls, tsserver, rust-analyzer on a big project) to load a workspace
-- and nothing else can speed that up from here; this is the way out of waiting for one that is not worth it.
local log = require "utils.log"

local M = {}

M.paused = false

--- Every server, including those that have not answered `initialize` yet: `vim.lsp.get_clients()` hides them, and they
--- are the ones worth stopping (a server stuck starting is not in the list but is reachable by its id, which counts up)
---@return vim.lsp.Client[]
function M.all()
  local out, seen = {}, {}
  for _, c in ipairs(vim.lsp.get_clients()) do
    seen[c.id] = true
    out[#out + 1] = c
  end
  for id = 1, M.max_id do
    local c = not seen[id] and vim.lsp.get_client_by_id(id) or nil
    if c and not c:is_stopped() then
      out[#out + 1] = c
    end
  end
  return out
end

--- How many ids are probed for the starting servers: far more than a session ever starts
M.max_id = 256

--- The servers of a buffer, and any still starting (those are not attached to anything yet)
---@param buf integer?
---@return vim.lsp.Client[]
function M.clients(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local out = {}
  for _, c in ipairs(M.all()) do
    if not c.initialized or (c.attached_buffers or {})[buf] then
      out[#out + 1] = c
    end
  end
  return out
end

---@param clients vim.lsp.Client[]
---@return string
local function names(clients)
  local out = {}
  for _, c in ipairs(clients) do
    out[#out + 1] = c.name
  end
  return table.concat(out, ", ")
end

--- Stops the servers of a buffer, also while they are still loading their workspace (a forced stop does not wait)
---@param buf integer?
---@return string[] stopped names
function M.stop(buf)
  local clients = M.clients(buf)
  if #clients == 0 then
    log.info "LSP: no server is running for this buffer"
    return {}
  end
  local stopped = {}
  for _, c in ipairs(clients) do
    stopped[#stopped + 1] = c.name
    c:stop(true)
  end
  log.info("LSP: stopped " .. table.concat(stopped, ", "))
  return stopped
end

--- Stops every server, of every project
---@return integer count
function M.stop_all()
  local clients = M.all()
  if #clients == 0 then
    log.info "LSP: no server is running"
    return 0
  end
  for _, c in ipairs(clients) do
    c:stop(true)
  end
  log.info("LSP: stopped " .. names(clients))
  return #clients
end

--- Stops and starts again the servers of a buffer (a server that got stuck, or a config that changed)
---@param buf integer?
function M.restart(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local servers = {}
  for _, c in ipairs(M.clients(buf)) do
    servers[#servers + 1] = c.name
    c:stop(true)
  end
  if #servers == 0 then
    log.info "LSP: no server is running for this buffer"
    return
  end
  -- once they are gone, the event that starts servers for a file is fired again (enabling a server that is already enabled
  -- does not look at buffers that exist)
  vim.defer_fn(function()
    for _, name in ipairs(servers) do
      vim.lsp.enable(name, true)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
    end
    log.info("LSP: restarted " .. table.concat(servers, ", "))
  end, 300)
end

--- Everything off until you resume: no server starts for any file, however many you open
function M.toggle_pause()
  -- the servers in use (Lua's is chosen at startup), not the ones the languages declare
  local list = require("servers").active
  if #list == 0 then
    list = require("languages").lsp_servers()
  end
  if M.paused then
    M.paused = false
    for _, name in ipairs(list) do
      vim.lsp.enable(name, true)
    end
    log.info "LSP: servers on again"
  else
    M.paused = true
    for _, name in ipairs(list) do
      vim.lsp.enable(name, false)
    end
    for _, c in ipairs(M.all()) do
      c:stop(true)
    end
    log.info "LSP: servers paused (<leader>Lp to resume)"
  end
  return M.paused
end

--- What the servers are doing right now (their progress), or that they are idle
---@return string
function M.status()
  local clients = M.all()
  if #clients == 0 then
    return M.paused and "paused" or "no server running"
  end
  local status = vim.trim(vim.lsp.status())
  return ("%s: %s"):format(names(clients), status ~= "" and status or "idle")
end

return M
