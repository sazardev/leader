-- Tests of stopping, restarting and pausing language servers (nvim/lua/utils/lspctl.lua). The "server" is a process that
-- never answers (sleep), which is what one stuck loading its workspace looks like. Hermetic: no real server, no network.
--   nvim -u NONE --headless -c "luafile scripts/test-lspctl.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if not vim.deep_equal(got, want) then
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end
local function wait(cond, ms)
  return vim.wait(ms or 4000, cond, 20)
end

vim.cmd "filetype plugin indent on"
vim.notify = function() end -- the messages are not what is under test
local ctl = require "utils.lspctl"
local function running()
  return #ctl.all()
end

local function stuck(name, buf)
  return vim.lsp.start({ name = name, cmd = { "sleep", "60" }, root_dir = "/tmp" }, { bufnr = buf, attach = true })
end

local ok_body, err_body = pcall(function()
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)

-- ── status ──────────────────────────────────────────────────────────────────
eq("status: nothing running", ctl.status(), "no server running")
eq("stop with no server stops nothing", ctl.stop(buf), {})
eq("stop all with no server stops nothing", ctl.stop_all(), 0)

-- ── a server that never finished loading can still be stopped ───────────────
local id = stuck("stuck_a", buf)
eq("a server still starting is found (get_clients() hides it)", #vim.lsp.get_clients(), 0)
eq("the stuck server is found by the control module", #ctl.clients(buf), 1)
eq("status names it", ctl.status():find("stuck_a", 1, true) ~= nil, true)
eq("stop returns what it stopped", ctl.stop(buf), { "stuck_a" })
eq("and it is gone, without waiting for it to answer", wait(function()
  return running() == 0
end), true)
local gone = vim.lsp.get_client_by_id(id)
eq("its client is stopped (or forgotten)", gone == nil or gone:is_stopped(), true)

-- ── stop all reaches every buffer and project ───────────────────────────────
local other = vim.api.nvim_create_buf(true, false)
stuck("stuck_b", buf)
stuck("stuck_c", other)
eq("two servers running", running(), 2)
eq("stop all counts them", ctl.stop_all(), 2)
eq("and none is left", wait(function()
  return running() == 0
end), true)

-- ── restart brings a configured server back as a new client ─────────────────
vim.lsp.config("restartable", {
  cmd = { "sleep", "60" },
  filetypes = { "lua" },
  root_dir = function(_, on_dir)
    on_dir "/tmp"
  end,
})
vim.lsp.enable "restartable"
vim.cmd("edit " .. vim.fn.tempname() .. ".lua")
buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = ""
vim.bo[buf].filetype = "lua"
eq("a configured server attaches by itself", wait(function()
  return #ctl.clients(buf) == 1
end), true)
local first = ctl.clients(buf)[1].id
ctl.restart(buf)
eq("restart: a different client takes its place", wait(function()
  local c = ctl.clients(buf)[1]
  return c ~= nil and c.id ~= first
end, 6000), true)
ctl.stop_all()
vim.lsp.enable("restartable", false)

-- ── pause and resume ────────────────────────────────────────────────────────
eq("not paused at first", ctl.paused, false)
eq("pausing says so", ctl.toggle_pause(), true)
eq("status while paused and idle", ctl.status(), "paused")
eq("resuming says so", ctl.toggle_pause(), false)
end)
if not ok_body then
  print("ERROR: " .. tostring(err_body))
  vim.cmd "cquit 1"
end

if fails > 0 then
  print(("FAILURES: %d of %d"):format(fails, total))
else
  print(("ALL OK (%d checks)"):format(total))
end
vim.cmd "qa!"
