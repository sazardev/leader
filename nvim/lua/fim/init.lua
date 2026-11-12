-- ── Local FIM completion (Qwen2.5-Coder, llama.cpp) ──────────────────────────
-- llama.vim draws the ghost text; this module owns the local server and the on/off switch. The model is the
-- llama.cpp preset `--fim-qwen-1.5b-default` (Q8, ~1.6 GB, downloaded on first start), a GGUF path, or `{ repo, file }`
-- from Hugging Face; the picker (`fim/picker.lua`, <leader>Sm / :Fim model) detects the machine and recommends one.
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
  if not model or model == "" or model == "preset" then
    return { "--fim-qwen-1.5b-default" }
  end
  local args
  if type(model) == "table" and model.repo then
    args = { "-hf", model.repo }
    if model.file and model.file ~= "" then
      vim.list_extend(args, { "--hf-file", model.file })
    end
  elseif type(model) == "string" then
    args = { "-m", vim.fn.expand(model) }
  else
    return { "--fim-qwen-1.5b-default" }
  end
  return vim.list_extend(args, { "--batch-size", "1024", "--ubatch-size", "1024", "--cache-reuse", "256" })
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

--- Starts the server if needed and calls cb(true) once it answers /health. cb(false) after 5 minutes (30 when the
--- model comes from Hugging Face: the first start also downloads the file).
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
    if tries > 0 and not pid_alive(read_pid()) then
      return cb(false) -- llama-server exited (bad model path, port in use, ...)
    end
    if tries == 0 then
      if not start() then
        return cb(false)
      end
      log.info "FIM: starting llama-server (the first start downloads the model)…"
    end
    local limit = type(cfg().model) == "table" and 3600 or 600
    if tries >= limit then
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
        log.info "FIM: ready (Ctrl+Tab accepts, Ctrl+Shift+Tab accepts one line)"
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

--- Toggles and REMEMBERS the choice (same place as <leader>Sp). With no model chosen yet, enabling opens the picker
--- instead of downloading the 1.5B preset silently.
---@param on boolean
function M.set_enabled(on)
  local store = require "prefs.store"
  if on and not cfg().model and store.read()["fim.model"] == nil then
    return M.pick_model {
      on_cancel = function()
        log.info "FIM: no model chosen, still off"
      end,
    }
  end
  store.save("fim.enabled", on)
  M.apply(on)
end

---@param pid integer?
---@param cb fun()
---@param tries integer?
local function wait_dead(pid, cb, tries)
  tries = tries or 0
  if pid_alive(pid) and tries < 50 then
    return vim.defer_fn(function()
      wait_dead(pid, cb, tries + 1)
    end, 100)
  end
  cb()
end

--- Switches to `model` (a GGUF path, `{ repo, file }`, or "preset") and `gpu_layers`, saves the choice, stops the old
--- server and starts the new one. It also turns FIM on.
---@param model string|table
---@param gpu_layers integer
function M.use(model, gpu_layers)
  local store = require "prefs.store"
  settings.fim.model = model
  settings.fim.gpu_layers = gpu_layers or 99
  settings.fim.enabled = true
  store.save("fim.model", model)
  store.save("fim.gpu_layers", settings.fim.gpu_layers)
  store.save("fim.enabled", true)
  ready = false
  refresh_statusline()
  local pid = read_pid()
  stop_server()
  wait_dead(pid, function()
    M.apply(true)
  end)
end

--- Opens the model picker (`<leader>Sm`, `:Fim model`, the settings panel).
---@param opts { on_cancel?: fun() }?
function M.pick_model(opts)
  require("fim.picker").open(opts)
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
    elseif args.args == "model" then
      M.pick_model()
    else
      M.toggle()
    end
  end, {
    nargs = "?",
    complete = function()
      return { "on", "off", "status", "model" }
    end,
    desc = "Local FIM completion: toggle / on / off / status / model",
  })

  if #vim.api.nvim_list_uis() == 0 or not enabled() or vim.g.light_mode then
    return
  end
  if not cfg().model and require("prefs.store").read()["fim.model"] == nil then
    log.info "FIM: using the 1.5B preset (:Fim model picks the best for this PC)"
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
