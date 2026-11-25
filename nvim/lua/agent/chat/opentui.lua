-- ── Optional OpenTUI chat bridge ─────────────────────────────────────────────
-- A second surface for the SAME chat runtime. OpenTUI owns only its terminal UI;
-- Neovim keeps sessions, context, model processes, streaming, history and writes.
-- The transport is two process-local atomic JSON files under Neovim's cache.
local settings = require "core.settings"

local M = {}

M.FILE = vim.fn.stdpath "cache" .. "/leader-chat-" .. vim.fn.getpid() .. ".json"
M.COMMANDS = vim.fn.stdpath "cache" .. "/leader-chat-" .. vim.fn.getpid() .. ".commands.json"

local timer
local last_json
local seen = {}
local seen_order = {}
local models = {}
local models_loading = false
local launched = false
local ack
local last_write = 0
local force_flush = false
local last_session, last_cwd
local last_updated, last_count = 0, 0
local last_profile, last_backend, last_model, last_effort
local last_running, last_sent_text, last_pending_text, last_pending_think
local last_ack_id, last_ack_ok, last_ack_error

---@return integer epoch milliseconds
local function now_ms()
  return os.time() * 1000 + math.floor((vim.uv.hrtime() % 1_000_000_000) / 1_000_000)
end

---@param text string?
---@param limit integer?
---@return string
local function clip(text, limit)
  text = text or ""
  limit = limit or 100_000
  if #text > limit then
    return vim.fn.strcharpart(text, 0, limit) .. "\n… (truncated in OpenTUI view)"
  end
  return text
end

---@param value any
---@return string?
local function clean(value)
  return type(value) == "string" and vim.trim(value) ~= "" and vim.trim(value) or nil
end

local function cfg()
  return settings.agent.chat.opentui or {}
end

---@return string?
function M.binary()
  local configured = clean(cfg().binary)
  if configured and vim.fn.executable(configured) == 1 then
    return configured
  end
  local on_path = vim.fn.exepath "leader-chat"
  if on_path ~= "" then
    return on_path
  end
  local source = vim.fn.resolve(debug.getinfo(1, "S").source:sub(2))
  local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))))
  for _, rel in ipairs {
    "app/target/chat/leader-chat",
    "app/tools/leader-chat/target/debug/leader-chat",
    "app/tools/leader-chat/target/release/leader-chat",
    "app/target/debug/leader-chat",
    "app/target/release/leader-chat",
  } do
    local path = root .. "/" .. rel
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  return nil
end

---@return table[]
function M.message_snapshot()
  local window = require "agent.chat.window"
  local session = window.session
  local out = {}
  if not session then
    return out
  end
  local budget = 2 * 1024 * 1024
  for i = #(session.messages or {}), 1, -1 do
    local msg = session.messages[i]
    local text = clip(msg.text, math.min(100_000, budget))
    budget = budget - #text
    local item = {
      id = ("%s:%d"):format(session.id, i),
      role = msg.role or "assistant",
      text = text,
      at = (msg.ts or os.time()) * 1000,
      state = msg.role == "tool" and "error" or "done",
    }
    if msg.usage then
      item.usage = msg.usage
    end
    if msg.role == "tool" then
      item.error = clip(msg.text, 2_000)
    end
    table.insert(out, 1, item)
    if budget <= 0 then
      break
    end
  end
  if window.running then
    local at = now_ms()
    if clean(window.sent_text) then
      out[#out + 1] = { id = "turn:user", role = "user", text = clip(window.sent_text), at = at, state = "done" }
    end
    out[#out + 1] = {
      id = "turn:assistant",
      role = "assistant",
      text = clip(window.pending_text),
      thinking = clip(window.pending_think),
      at = at,
      state = "running",
    }
  end
  return out
end

---@return table
function M.snapshot()
  local chat = require "agent.chat"
  local window = require "agent.chat.window"
  local session = chat.active_session()
  local root = session and session.root or (vim.fs.root(0, ".git") or vim.uv.cwd() or "")
  local profiles = vim.tbl_map(function(profile)
    return { id = profile.id, label = profile.label }
  end, require("agent.chat.profiles").list())
  local current_models = {}
  local seen_models = {}
  local function add_model(backend, model, label)
    if not backend or not model then
      return
    end
    local id = ("%s/%s"):format(backend, model)
    if not seen_models[id] then
      seen_models[id] = true
      current_models[#current_models + 1] = { id = id, label = label or model }
    end
  end
  for _, model in ipairs(models) do
    add_model(model.backend, model.model, model.label)
  end
  if session then
    add_model(session.backend, session.model)
  end
  local selection = require("agent.selection").current()
  if selection then
    add_model(selection.backend, selection.model)
  end
  local history = vim.tbl_map(function(entry)
    return {
      id = entry.id,
      title = entry.title,
      at = (entry.updated or 0) * 1000,
      model = entry.model and ((entry.backend and (entry.backend .. "/") or "") .. entry.model)
        or entry.backend
        or "unknown",
    }
  end, chat.history(root))
  local session_data
  if session then
    session_data = {
      id = session.id,
      title = session.title,
      model = session.model and ((session.backend and (session.backend .. "/") or "") .. session.model)
        or session.backend
        or "",
      profile = session.profile or settings.agent.chat.profile or "write",
      effort = session.effort,
      running = window.running,
    }
  else
    session_data = {
      id = "draft",
      title = "New chat",
      model = "",
      profile = settings.agent.chat.profile or "write",
      running = false,
    }
  end
  return {
    version = 1,
    pid = vim.fn.getpid(),
    cwd = vim.uv.cwd() or "",
    updated_at = now_ms(),
    session = session_data,
    messages = M.message_snapshot(),
    ack = ack,
    profiles = profiles,
    models = current_models,
    history = history,
  }
end

---@return boolean
function M.flush()
  if cfg().enabled == false then
    return false
  end
  local window = require "agent.chat.window"
  local session = window.session
  local cwd = vim.uv.cwd() or ""
  local changed = force_flush
    or session ~= last_session
    or cwd ~= last_cwd
    or (session and (session.updated ~= last_updated or #(session.messages or {}) ~= last_count))
    or (session and (session.profile ~= last_profile or session.backend ~= last_backend or session.model ~= last_model or session.effort ~= last_effort))
    or window.running ~= last_running
    or window.sent_text ~= last_sent_text
    or window.pending_text ~= last_pending_text
    or window.pending_think ~= last_pending_think
    or (ack and (ack.id ~= last_ack_id or ack.ok ~= last_ack_ok or ack.error ~= last_ack_error))
  if not changed and vim.uv.now() - last_write < 5000 then
    return true
  end
  local data = M.snapshot()
  local stamp = data.updated_at
  data.updated_at = 0
  local normalized = vim.json.encode(data)
  if normalized == last_json and vim.uv.now() - last_write < 5000 then
    return true
  end
  last_json = normalized
  last_write = vim.uv.now()
  force_flush = false
  last_session, last_cwd = session, cwd
  last_updated = session and session.updated or 0
  last_count = session and #(session.messages or {}) or 0
  last_profile = session and session.profile or nil
  last_backend = session and session.backend or nil
  last_model = session and session.model or nil
  last_effort = session and session.effort or nil
  last_running = window.running
  last_sent_text, last_pending_text, last_pending_think = window.sent_text, window.pending_text, window.pending_think
  last_ack_id, last_ack_ok, last_ack_error = ack and ack.id or nil, ack and ack.ok or nil, ack and ack.error or nil
  data.updated_at = stamp
  local json = vim.json.encode(data)
  vim.fn.mkdir(vim.fs.dirname(M.FILE), "p")
  local tmp = M.FILE .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    return false
  end
  f:write(json)
  f:close()
  local ok = vim.uv.fs_rename(tmp, M.FILE)
  if not ok then
    os.remove(M.FILE)
    ok = vim.uv.fs_rename(tmp, M.FILE)
  end
  if ok then
    pcall(vim.uv.fs_chmod, M.FILE, 384) -- 0600: the feed contains conversation text
  end
  if not ok then
    force_flush = true
  end
  return ok
end

local function remember(id)
  if seen[id] then
    return false, seen[id]
  end
  seen[id] = { ok = true }
  seen_order[#seen_order + 1] = id
  if #seen_order > 100 then
    seen[table.remove(seen_order, 1)] = nil
  end
  return true
end

---@param id string
---@param ok boolean
---@param error string?
local function acknowledge(id, ok, error)
  ack = { id = id, ok = ok, error = error }
end

---@param command table
---@return boolean ok, string? error
function M.handle(command)
  if type(command) ~= "table" or command.version ~= 1 or not clean(command.id) or not clean(command.action) then
    return false, "invalid command"
  end
  local fresh, previous = remember(command.id)
  if not fresh then
    acknowledge(command.id, previous.ok, previous.error)
    force_flush = true
    return previous.ok, previous.error
  end
  local function fail(error)
    seen[command.id] = { ok = false, error = error }
    acknowledge(command.id, false, error)
    force_flush = true
    return false, error
  end
  local chat = require "agent.chat"
  local action = command.action
  if action == "send" then
    local text = clean(command.text)
    if not text then
      return fail "send needs text"
    end
    local slash = text:match "^/(%w+)"
    if slash == "new" then
      if not chat.new_headless() then
        return fail "chat is still running"
      end
    elseif slash == "clear" then
      chat.clear()
    elseif slash == "history" then
      -- the TUI already has the history list in its snapshot
    elseif slash and require("agent.chat.commands").has(slash) then
      return fail("use the OpenTUI controls for /" .. slash)
    else
      chat.ensure_session()
      if not chat.send(text) then
        return fail "message was not accepted"
      end
    end
  elseif action == "stop" then
    chat.stop()
  elseif action == "new" then
    if not chat.new_headless() then
      return fail "chat is still running"
    end
  elseif action == "history" then
    -- the snapshot already carries the history list
  elseif action == "select_session" then
    if not chat.open_session(command.session_id or "") then
      return fail "session not found or chat is running"
    end
  elseif action == "set_profile" then
    if not chat.configure { profile = command.value } then
      return fail "profile unavailable or chat is running"
    end
  elseif action == "set_model" then
    local backend, model = (command.value or ""):match "^([^/]+)/(.+)$"
    if not backend or not model or not chat.configure { backend = backend, model = model } then
      return fail "model unavailable or chat is running"
    end
  else
    return fail "unknown action: " .. action
  end
  acknowledge(command.id, true)
  seen[command.id] = { ok = true }
  force_flush = true
  return true
end

--- Reads at most one command. If a newer command replaced the file while it was handled, the new one stays for the
--- next tick. This avoids losing a fast second command between read and unlink.
function M.poll_once()
  local f = io.open(M.COMMANDS, "r")
  if not f then
    return
  end
  local raw = f:read "*a"
  f:close()
  local ok, command = pcall(vim.json.decode, raw)
  if not ok then
    os.remove(M.COMMANDS)
    return
  end
  local ok_handle, handled, err = pcall(M.handle, command)
  if not ok_handle then
    if type(command) == "table" and clean(command.id) then
      seen[command.id] = { ok = false, error = tostring(handled) }
      acknowledge(command.id, false, tostring(handled))
      force_flush = true
    end
    vim.notify("OpenTUI Chat: " .. tostring(handled), vim.log.levels.ERROR)
  elseif not handled and err then
    vim.notify("OpenTUI Chat: " .. err, vim.log.levels.WARN)
  end
  M.flush()
  local check = io.open(M.COMMANDS, "r")
  if check then
    local current = check:read "*a"
    check:close()
    if current == raw then
      os.remove(M.COMMANDS)
    end
  end
end

function M.refresh_models()
  if models_loading then
    return
  end
  models_loading = true
  require("agent.chat").models(function(items)
    models = items or {}
    models_loading = false
    force_flush = true
    vim.schedule(M.flush)
  end)
end

local function tick()
  M.poll_once()
  M.flush()
  if launched then
    local term = require("utils.terminal").named "OpenTUI Chat"
    if not term or vim.fn.jobpid(term.job_id or 0) <= 0 then
      M.close()
    end
  end
end

function M.start()
  if timer then
    return
  end
  timer = assert(vim.uv.new_timer())
  timer:start(100, 100, vim.schedule_wrap(tick))
end

function M.close()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  launched = false
  last_json = nil
  last_write = 0
  ack = nil
  force_flush = false
  last_session, last_cwd = nil, nil
  last_updated, last_count = 0, 0
  last_profile, last_backend, last_model, last_effort = nil, nil, nil, nil
  last_running, last_sent_text, last_pending_text, last_pending_think = nil, nil, nil, nil
  last_ack_id, last_ack_ok, last_ack_error = nil, nil, nil
  os.remove(M.FILE)
  os.remove(M.COMMANDS)
end

--- Test hook: forget transport state without touching files.
function M.reset()
  M.close()
  seen, seen_order, models = {}, {}, {}
  models_loading = false
end

function M.setup()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("LeaderOpenTUIChat", { clear = true }),
    callback = M.close,
  })
end

---@return boolean
function M.is_open()
  local term = require("utils.terminal").named "OpenTUI Chat"
  return term ~= nil and term:is_open()
end

function M.open()
  if settings.agent.chat.enabled == false or cfg().enabled == false then
    vim.notify("OpenTUI Chat is disabled", vim.log.levels.WARN)
    return
  end
  local binary = M.binary()
  if not binary then
    vim.notify("OpenTUI Chat is not built. Run: make chat", vim.log.levels.WARN)
    return
  end
  M.setup()
  last_json = nil
  os.remove(M.COMMANDS)
  require("agent.chat").ensure_session()
  M.refresh_models()
  M.start()
  M.flush()
  pcall(require("lazy").load, { plugins = { "toggleterm.nvim" } })
  local cmd = ("%s --state %s --commands %s"):format(
    vim.fn.shellescape(binary),
    vim.fn.shellescape(M.FILE),
    vim.fn.shellescape(M.COMMANDS)
  )
  require("utils.terminal").float_repl("OpenTUI Chat", cmd, vim.uv.cwd() or vim.fn.getcwd())
  launched = true
end

return M
