-- Restarts a language server that outgrew its memory limit (settings.lsp.memory_limit_mb). tsserver keeps every
-- project it has seen, so in a monorepo a long session reaches 3 GB; restarting it reloads the project (1-3 s) and
-- frees all of it. It only happens when you have been idle, never while typing.
local M = {}

--- Total RSS (MB) of the processes under `root` whose command line contains `needle`
---@param ps string output of `ps -eo pid=,ppid=,rss=,args=`
---@param root integer
---@param needle string
---@return number
function M.tree_mb(ps, root, needle)
  local kids, info = {}, {}
  for line in ps:gmatch "[^\n]+" do
    local pid, ppid, rss, args = line:match "^%s*(%d+)%s+(%d+)%s+(%d+)%s+(.*)$"
    if pid then
      pid, ppid = tonumber(pid), tonumber(ppid)
      info[pid] = { rss = tonumber(rss), args = args }
      kids[ppid] = kids[ppid] or {}
      table.insert(kids[ppid], pid)
    end
  end
  local total = 0
  local function walk(pid)
    for _, c in ipairs(kids[pid] or {}) do
      if info[c].args:find(needle, 1, true) then
        total = total + info[c].rss
      end
      walk(c)
    end
  end
  walk(root)
  return total / 1024
end

--- Whether to restart: over the limit, and idle long enough
---@param mb number
---@param limit number? 0 or nil = off
---@param idle_s number seconds since the last key
---@param min_idle_s number
---@return boolean
function M.should_restart(mb, limit, idle_s, min_idle_s)
  return (limit or 0) > 0 and mb > limit and idle_s >= min_idle_s
end

local last_key = vim.uv.hrtime()

--- A project whose server starts above the limit would restart it every check: after a restart, leave it alone
M.cooldown_s = 600
local restarted = {} ---@type table<string, number> server → hrtime of its last restart

function M.setup()
  local cfg = require("core.settings").lsp
  local limits = cfg.memory_limit_mb or {}
  if next(limits) == nil then
    return
  end
  vim.on_key(function()
    last_key = vim.uv.hrtime()
  end, vim.api.nvim_create_namespace "memguard")

  local busy = false
  local timer = vim.uv.new_timer()
  timer:start(
    cfg.memory_check_s * 1000,
    cfg.memory_check_s * 1000,
    vim.schedule_wrap(function()
      local idle = (vim.uv.hrtime() - last_key) / 1e9
      if busy or idle < cfg.memory_idle_s or vim.api.nvim_get_mode().mode:find "^[iR]" then
        return
      end
      busy = true
      vim.system({ "ps", "-eo", "pid=,ppid=,rss=,args=" }, { text = true }, function(res)
        vim.schedule(function()
          busy = false
          if res.code ~= 0 then
            return
          end
          for name, limit in pairs(limits) do
            if #vim.lsp.get_clients { name = name } > 0 then
              local mb = M.tree_mb(res.stdout, vim.uv.os_getpid(), name)
              local idle_now = (vim.uv.hrtime() - last_key) / 1e9
              local cooled = (vim.uv.hrtime() - (restarted[name] or -math.huge)) / 1e9 >= M.cooldown_s
              if cooled and M.should_restart(mb, limit, idle_now, cfg.memory_idle_s) then
                restarted[name] = vim.uv.hrtime()
                require("utils.log").info(("%s used %.0f MB (limit %d): restarting it"):format(name, mb, limit))
                vim.cmd("lsp restart " .. name)
              end
            end
          end
        end)
      end)
    end)
  )
end

return M
