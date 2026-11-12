-- ── Local FIM completion (Qwen2.5-Coder, llama.cpp) ──────────────────────────
-- llama.vim draws the ghost text; this module owns the local server and the on/off switch. The model is the
-- llama.cpp preset `--fim-qwen-1.5b-default` (Q8, ~1.6 GB, downloaded on first start) or the GGUF in
-- `settings.fim.model` (with the preset's batch/cache values), served on 127.0.0.1.
local settings = require "core.settings"
local log = require "utils.log"

local M = {}

local STATE = vim.fn.stdpath "state" .. "/fim"
local PID = STATE .. "/server.pid"
local LOG = STATE .. "/server.log"
local PLUGIN = "llama.vim"

local ready = false

local function refresh_statusline()
  pcall(function()
    require("lualine").refresh()
  end)
end

local function cfg()
  return settings.fim
end

local function port()
  return cfg().port or 8012
end

local function base()
  return ("http://127.0.0.1:%d"):format(port())
end

--- The built-in preset selects the model and tunes the server for FIM. A custom GGUF (`settings.fim.model`) has to
--- carry the same batch and cache values, or it runs with llama.cpp's defaults.
local function model_args()
  local model = cfg().model
  if not model or model == "" then
    return { "--fim-qwen-1.5b-default" }
  end
  return {
    "-m",
    vim.fn.expand(model),
    "--batch-size",
    "1024",
    "--ubatch-size",
    "1024",
    "--cache-reuse",
    "256",
  }
end

local function enabled()
  return cfg().enabled == true
end

local function read_pid()
  local f = io.open(PID, "r")
  if not f then
    return nil
  end
  local pid = tonumber(f:read "*a")
  f:close()
  return pid
end

local function pid_alive(pid)
  if not pid then
    return false
  end
  local ok, res = pcall(vim.uv.kill, pid, 0)
  return ok and res == 0
end

local function start()
  local pid = read_pid()
  if pid_alive(pid) then
    return true
  end
  if vim.fn.executable "llama-server" == 0 then
    log.warn "FIM: llama-server is not installed (it comes with llama.cpp)"
    return false
  end
  if vim.fn.executable "sh" == 0 then
    log.warn "FIM: sh is required to start llama-server in the background"
    return false
  end
  vim.fn.mkdir(STATE, "p")
  local args = { "llama-server" }
  vim.list_extend(args, model_args())
  vim.list_extend(args, {
    "--host",
    "127.0.0.1",
    "--port",
    tostring(port()),
    "--ctx-size",
    tostring(cfg().context or 8192),
    "--n-gpu-layers",
    tostring(cfg().gpu_layers or 99),
    "--parallel",
    "1",
    "--no-webui",
    "--sleep-idle-seconds",
    tostring(cfg().sleep_idle or 300),
    "--log-verbosity",
    "1",
  })
  local line = table.concat(vim.tbl_map(vim.fn.shellescape, args), " ") .. " >> " .. vim.fn.shellescape(LOG) .. " 2>&1"
  local handle, spawned = vim.uv.spawn("sh", {
    args = { "-c", "exec " .. line },
    detached = true,
    stdio = { nil, nil, nil },
  })
  if not handle then
    log.warn("FIM: could not start llama-server: " .. tostring(spawned))
    return false
  end
  local pid_started = spawned
  handle:close()
  vim.fn.writefile({ tostring(pid_started) }, PID)
  return true
end

local function stop_server()
  local pid = read_pid()
  os.remove(PID)
  if pid_alive(pid) then
    pcall(vim.uv.kill, pid, "sigterm")
    vim.defer_fn(function()
      if pid_alive(pid) then
        pcall(vim.uv.kill, pid, "sigkill")
      end
    end, 2000)
  end
end

local function health(cb)
  if vim.fn.executable "curl" == 0 then
    return cb(false)
  end
  vim.system({ "curl", "-fsS", "--max-time", "0.5", base() .. "/health" }, { text = true }, function(out)
    vim.schedule(function()
      cb(out.code == 0)
    end)
  end)
end

--- Starts the server if needed and calls cb(true) once it answers /health. cb(false) after 5 minutes.
---@param cb fun(ok: boolean)
---@param tries integer?
function M.ensure(cb, tries)
  tries = tries or 0
  if not enabled() then
    return cb(false)
  end
  health(function(ok)
    if ok then
      return cb(true)
    end
    if tries == 0 then
      if not start() then
        return cb(false)
      end
      log.info "FIM: starting llama-server (the first start downloads the model)…"
    end
    if tries >= 600 then
      return cb(false)
    end
    vim.defer_fn(function()
      M.ensure(cb, tries + 1)
    end, 500)
  end)
end

--- llama.vim is a Vimscript plugin, so `package.loaded` never sees it; its autoload function is the probe.
---@return boolean
local function plugin_loaded()
  return vim.fn.exists "*llama#is_fim_hint_shown" == 1
end

--- Loads llama.vim and enables it; safe to call repeatedly. Returns false when the plugin is not installed.
function M.load_plugin()
  if not plugin_loaded() then
    pcall(require("lazy").load, { plugins = { PLUGIN } })
  end
  if not plugin_loaded() then
    log.warn "FIM: llama.vim is not installed (run :Lazy sync)"
    return false
  end
  pcall(vim.cmd, "LlamaEnable")
  return true
end

--- Applies the current setting: off stops the server; on starts it and loads the ghost-text plugin.
---@param on boolean
function M.apply(on)
  settings.fim.enabled = on
  if on then
    ready = false
    refresh_statusline()
    M.ensure(function(ok)
      if not settings.fim.enabled then
        return
      end
      if ok then
        if not M.load_plugin() then
          return
        end
        ready = true
        refresh_statusline()
        log.info "FIM: ready (Tab accepts, Shift+Tab accepts one line)"
      else
        log.warn("FIM: llama-server did not become ready; see " .. LOG)
      end
    end)
  else
    if plugin_loaded() then
      pcall(vim.cmd, "LlamaDisable")
    end
    ready = false
    stop_server()
    refresh_statusline()
    log.info "FIM: off"
  end
end

--- Toggles and REMEMBERS the choice (same place as <leader>Sp).
---@param on boolean
function M.set_enabled(on)
  require("prefs.store").save("fim.enabled", on)
  M.apply(on)
end

function M.toggle()
  M.set_enabled(not enabled())
end

--- What lualine shows: nothing when off, `FIM…` while the server starts, `FIM` when ready.
---@return string
function M.statusline()
  if not enabled() then
    return ""
  end
  return ready and "FIM" or "FIM…"
end

--- Called once at startup: warm the server in the background when the setting is on. Headless runs do nothing.
function M.setup()
  -- These are global on purpose: llama.vim only maps them while a hint is visible, but the user asked for the same keys
  -- in every insert buffer (code, chat, modals). With no hint they do nothing.
  local function accept(kind)
    if vim.fn.exists "*llama#is_fim_hint_shown" == 1 and vim.fn["llama#is_fim_hint_shown"]() then
      pcall(vim.fn["llama#fim_accept"], kind)
    end
  end
  vim.keymap.set("i", "<C-Tab>", function()
    accept "full"
  end, { desc = "Completion accept local FIM suggestion" })
  vim.keymap.set("i", "<C-S-Tab>", function()
    accept "line"
  end, { desc = "Completion accept first line of local FIM suggestion" })

  vim.api.nvim_create_user_command("Fim", function(args)
    if args.args == "on" then
      M.set_enabled(true)
    elseif args.args == "off" then
      M.set_enabled(false)
    elseif args.args == "status" then
      health(function(ok)
        log.info(("FIM: %s, server %s"):format(enabled() and "on" or "off", ok and "ready" or "not running"))
      end)
    else
      M.toggle()
    end
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "status" }
    end,
    desc = "Local FIM completion: toggle / on / off / status",
  })

  if #vim.api.nvim_list_uis() == 0 or not enabled() or vim.g.light_mode then
    return
  end
  vim.defer_fn(function()
    M.ensure(function(ok)
      if ok and settings.fim.enabled then
        if not M.load_plugin() then
          return
        end
        ready = true
        refresh_statusline()
      end
    end)
  end, 200)
end

return M
