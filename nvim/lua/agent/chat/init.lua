-- Chat facade (<leader>aC): a persistent, backend-agnostic chat under Leader.
-- Claude Code + Opencode shape (right panel, streaming, thinking, /commands,
-- @files, #skills, $mcp, model + effort pickers), but Leader orchestrates:
-- every turn is shown transparently (what was injected, tokens, cost, time) and
-- persisted per project. Hiding the panel keeps the session; statusline shows it.
local M = {}

---@return table session (create or load the last one for this project)
local function current()
  local window = require "agent.chat.window"
  if window.session then
    return window.session
  end
  local root = vim.fs.root(0, ".git") or (vim.uv.cwd() or "")
  local session = require("agent.chat.store").last_for_root(root)
  if not session then
    session = require("agent.chat.session").new { root = root }
    local sel = require("agent.selection").current()
    if sel then
      session.backend, session.model, session.effort = sel.backend, sel.model, sel.effort
    end
    require("agent.chat.store").put(session)
  end
  window.session = session
  return session
end

--- Toggle the panel (open / hide). <leader>aC.
--- Already open but not focused: it comes forward instead of disappearing.
function M.open()
  if not require("core.settings").agent.chat.enabled then
    return require("utils.log").warn "Chat: disabled (settings.agent.chat.enabled = false)"
  end
  local window = require "agent.chat.window"
  current()
  if window.is_open() then
    local cur = vim.api.nvim_get_current_win()
    if cur == window.input_win or cur == window.transcript_win then
      window.toggle() -- focused: hide
    else
      window.focus() -- open behind the code: bring it forward
    end
  else
    window.toggle()
  end
  if not window.is_open() then
    require("utils.log").error "Chat: could not open the panel (:messages has the error)"
  end
end

--- Collapse to the right-edge rail (or expand again). <C-t> inside the panel.
function M.toggle_collapse()
  local window = require "agent.chat.window"
  current()
  window.toggle_collapse()
end

--- Mini (right panel) or fullscreen. <C-f> inside the panel, :Chat full/mini.
---@param view "mini"|"full"
function M.set_view(view)
  local window = require "agent.chat.window"
  current()
  if not window.is_open() then
    window.view = view
    return
  end
  window.set_view(view)
end

--- Toggle mini <-> full.
function M.toggle_view()
  local window = require "agent.chat.window"
  current()
  if not window.is_open() then
    window.view = window.current_view() == "full" and "mini" or "full"
    return
  end
  window.toggle_view()
end

--- Start a fresh session in this project.
function M.new_session()
  local window = require "agent.chat.window"
  local root = vim.fs.root(0, ".git") or (vim.uv.cwd() or "")
  local session = require("agent.chat.session").new { root = root }
  local sel = require("agent.selection").current()
  if sel then
    session.backend, session.model, session.effort = sel.backend, sel.model, sel.effort
  end
  require("agent.chat.store").put(session)
  window.session = session
  window.pending_text, window.pending_think, window.injected_names = "", "", nil
  window.toggle_hide = nil
  if window.is_open() then
    window.draw()
  else
    window.toggle()
  end
  -- focus the input
  if window.input_win then
    vim.api.nvim_set_current_win(window.input_win)
    vim.cmd "startinsert"
  end
end

--- Pick a session (history): restores model/effort with it.
function M.pick_session()
  local items = require("agent.chat.store").list()
  if #items == 0 then
    return require("utils.log").info "Chat: no sessions yet"
  end
  local rows = vim.tbl_map(function(s)
    return {
      label = ("%s · %s · %d msg"):format(
        s.title ~= "" and s.title or "chat",
        require("agent.text").tokens((s.tokens_in or 0) + (s.tokens_out or 0)) .. " tok",
        #(s.messages or {})
      ),
      id = s.id,
      current = require("agent.chat.window").session and require("agent.chat.window").session.id == s.id,
    }
  end, items)
  require("agent.ui.select").pick(rows, { title = "Chat · sessions" }, function(choice)
    local session = require("agent.chat.store").get(choice.id)
    if session then
      local window = require "agent.chat.window"
      window.session = session
      if not window.is_open() then
        window.toggle()
      else
        window.draw()
      end
    end
  end)
end

--- Every model of every installed backend. `chat_models` (when a backend has it)
--- ignores the one-shot shortlist: opencode lists everything `opencode models` knows.
--- A backend that never answers (a stuck service) cannot block the picker: after
--- `MODELS_TIMEOUT_MS` the ones received so far are offered.
---@param cb fun(models: table[])
function M.models(cb)
  local backends = require "agent.backends"
  local available = backends.available()
  if #available == 0 then
    return cb {}
  end
  local groups, pending, settled = {}, #available, false
  local function finish()
    if settled then
      return
    end
    settled = true
    local items = {}
    for _, group in ipairs(groups) do
      vim.list_extend(items, group)
    end
    cb(items)
  end
  for i, backend in ipairs(available) do
    local list = backend.chat_models or backend.models
    local answered = false
    local function got(models)
      if answered then
        return
      end
      answered = true
      groups[i] = vim.tbl_map(function(m)
        return { backend = backend.name, model = m.id, label = m.label or m.id }
      end, models or {})
      pending = pending - 1
      if pending == 0 then
        finish()
      end
    end
    local ok = pcall(list, got)
    if not ok then
      got {}
    end
  end
  vim.defer_fn(finish, 7000)
end

--- Pick backend + model (agnostic: any available backend, ALL its models).
--- Only on demand (<C-M> / /model): sending never interrupts you with it.
function M.pick_model()
  local session = current()
  M.models(function(items)
    if #items == 0 then
      return require("agent.chooser").none()
    end
    local width = 0
    for _, it in ipairs(items) do
      width = math.max(width, vim.fn.strdisplaywidth(it.backend))
    end
    for _, it in ipairs(items) do
      it.label = ("%-" .. (width + 2) .. "s %s"):format(it.backend, it.label)
      it.current = session.backend == it.backend and session.model == it.model
    end
    require("agent.ui.select").pick(items, { title = "Chat · model" }, function(choice)
      session.backend, session.model = choice.backend, choice.model
      session.effort = nil
      require("agent.chat.store").put(session)
      require("agent.chat.window").draw()
      require("utils.log").info(("Chat: %s/%s"):format(choice.backend, choice.model))
    end)
  end)
end

--- Pick effort for the chat's backend (low/medium/high/... when it supports it).
function M.pick_effort()
  local session = current()
  local backends = require "agent.backends"
  local backend = backends.get(session.backend or (require("agent.selection").current() or {}).backend or "")
  if not backend or not backend.efforts then
    return require("utils.log").info "Chat: this backend has no effort levels"
  end
  local items = { { label = "default (the model's own)", value = nil, current = not session.effort } }
  for _, level in ipairs(backend.efforts) do
    items[#items + 1] = { label = level, value = level, current = session.effort == level }
  end
  require("agent.ui.select").pick(items, { title = "Chat · effort" }, function(choice)
    session.effort = choice.value
    require("agent.chat.store").put(session)
    require("agent.chat.window").draw()
    require("utils.log").info("Chat: effort " .. tostring(choice.value or "default"))
  end)
end

--- Draft an ADR from the current session into docs/adr/.
function M.draft_adr()
  local session = current()
  local root = session.root or (vim.fs.root(0, ".git") or vim.uv.cwd() or "")
  require("utils.log").info "Chat: drafting ADR…"
  require("agent.chat.adr").from_session(session, root, function(path, err)
    if path then
      require("utils.log").info(("Chat: ADR written — %s"):format(path))
      vim.fn.system { "git", "-C", root, "add", path }
      M.export()
    else
      require("utils.log").warn(("Chat: %s"):format(err or "ADR failed"))
    end
  end)
end

--- Copy the transcript to the clipboard (and save nothing extra).
function M.export()
  local session = current()
  local lines = require("agent.chat.render").lines(session, {})
  local text = table.concat(lines, "\n") .. "\n"
  require("agent.ui.clipboard").copy(text, "transcript")
end

--- Clear the current session's messages (keeps the model/effort).
function M.clear()
  local session = current()
  session.messages = {}
  session.tokens_in, session.tokens_out, session.cost, session.turns = 0, 0, 0, 0
  require("agent.chat.store").put(session)
  require("agent.chat.window").draw()
end

--- Stop the running turn (if any).
function M.stop()
  require("agent.calls").cancel() -- run via calls, so this is its handle
  local window = require "agent.chat.window"
  window.set_running(false)
  window.pending_text, window.pending_think = "", ""
  window.draw()
end

--- Show help (only on demand: the chrome shows just "⏎ send").
function M.help()
  local lines = {
    "Leader Chat — help",
    "",
    "Send: ⏎ · New line: Shift-⏎ · Hide: q / Ctrl-Q (session keeps running).",
    "Triggers, filtered as you type (⏎/Tab accepts): / commands · @ project files (@buf, @sel, @diag) · # skills · $ MCP.",
    "Commands: /new · /model · /effort · /clear · /adr · /export · /full · /mini · /collapse · /help.",
    "Input: ↑/↓ previous messages · Shift-⏎ new line · it grows with the text.",
    "View: Ctrl-F (mini/full) · Ctrl-T (collapse to rail).",
    "Keys: Ctrl-N · Ctrl-H · Ctrl-M · Ctrl-E · Ctrl-A · Ctrl-X.",
    "Transcript: y copy message · c copy its code block · Y copy all · o view message · h history · i input · q hide.",
  }
  require("agent.ui.panel").open(lines, "Leader Chat · help")
end

--- Send one user turn: parse mentions, collect context, run a turn.
--- `⏎` sends with whatever is already selected (session > <leader>am > the
--- backend's default model): no picker, no extra step. A backend that needs a
--- model and has none resolves one silently (the CLI's first) and says which.
---@param raw string text from the input box
---@return boolean accepted the input can be cleared
function M.send(raw)
  raw = raw or ""
  raw = raw:gsub("^%s*(.-)%s*$", "%1")
  if raw == "" then
    return false
  end
  local window = require "agent.chat.window"
  if window.running and not raw:match "^/" then
    require("utils.log").warn "Chat: still answering (Ctrl-X stops it)"
    return false
  end
  local session = current()
  local sel = require("agent.selection").current()
  -- session model wins over the global selection when the user picked one in chat;
  -- a session on ANOTHER backend never borrows that backend's model/effort
  local backend_name = session.backend or (sel and sel.backend)
  local same = sel and sel.backend == backend_name
  local eff_sel = {
    backend = backend_name,
    model = session.model or (same and sel.model or nil),
    effort = session.effort or (same and sel.effort or nil),
    tier = "main",
  }
  if not eff_sel.backend then
    require("utils.log").warn "Chat: no backend (run <leader>am → Setup)"
    return false
  end

  local function turn(choice)
    local clean, mentions, slash = require("agent.chat.mention").parse(raw)
    if slash then
      if slash == "new" then
        M.new_session()
      elseif slash == "clear" then
        M.clear()
      elseif slash == "model" then
        M.pick_model()
      elseif slash == "effort" then
        M.pick_effort()
      elseif slash == "adr" then
        M.draft_adr()
      elseif slash == "export" then
        M.export()
      elseif slash == "collapse" then
        M.toggle_collapse()
      elseif slash == "full" then
        M.set_view "full"
      elseif slash == "mini" then
        M.set_view "mini"
      elseif slash == "help" then
        M.help()
      end
      return
    end
    if clean == "" and #mentions == 0 then
      return
    end

    -- auto context (what Leader injects besides the messages); a broken provider
    -- must not kill the turn (agent/context lets providers fail the same way)
    local auto = {}
    local ok_auto, got = pcall(require("agent.chat.context").collect)
    if ok_auto and got then
      auto = got
    elseif not ok_auto then
      require("utils.log").warn(("Chat: context skipped: %s"):format(tostring(got):sub(1, 160)))
    end
    local sections = vim.list_extend({}, mentions)
    vim.list_extend(sections, type(auto) == "table" and auto or {})
    require("agent.chat.window").injected_names = vim.tbl_map(function(s)
      return s.name
    end, sections)

    local system, prompt, injected = require("agent.chat.prompt").build(session, clean, sections)

    -- budget guard: same estimate as one-shot actions (chars/3.5), ask above the limits
    local guard_req = {
      action = "chat",
      backend = choice.backend,
      model = choice.model,
      chars = #system + #prompt,
      sections = vim.tbl_map(function(s)
        return { name = s.name, chars = #s.text }
      end, sections),
    }
    local function proceed()
      require("agent.chat.window").clear_input()
      M._launch(session, choice, clean, system, prompt, injected)
    end
    local function deny(why)
      require("utils.log").warn("Chat: " .. tostring(why or "cancelled"))
    end
    require("agent.guards").check(guard_req, proceed, deny)
  end

  -- No picker on send: a backend that needs a model and has none gets its first
  -- (or its default) silently, remembered for the next turns.
  local backend = require("agent.backends").get(eff_sel.backend)
  if not backend.requires_model or eff_sel.model then
    turn(eff_sel)
    return true
  end
  local function use(model)
    eff_sel.model = model
    session.backend, session.model = eff_sel.backend, model
    require("agent.chat.store").put(session)
    require("utils.log").info(("Chat: using %s"):format(model))
    turn(eff_sel)
  end
  if backend.default_model and backend.default_model ~= "" then
    use(backend.default_model)
    return true
  end
  local list = backend.chat_models or backend.models
  list(function(models)
    if models and models[1] then
      use(models[1].id)
    else
      require("utils.log").warn(
        ("Chat: no model available for %s (run <leader>am)"):format(backend.label or backend.name)
      )
    end
  end)
  return true
end

---@param session table
---@param sel table
---@param clean string
---@param system string
---@param prompt string
---@param injected string[]
function M._launch(session, sel, clean, system, prompt, injected)
  local window = require "agent.chat.window"
  window.set_running(true)
  window.pending_text, window.pending_think = "", ""
  -- stream throttled like every other agent UI (settings.agent.stream_ms)
  local last_draw = 0
  local stream_gap = (require("core.settings").agent.stream_ms or 40) * 1e6
  local function draw_soon()
    local now = vim.uv.hrtime()
    if now - last_draw < stream_gap then
      vim.defer_fn(function()
        last_draw = vim.uv.hrtime()
        window.draw()
      end, 35)
      return
    end
    last_draw = now
    window.draw()
  end

  local function cleanup(ok, usage, err)
    window.set_running(false)
    window.pending_text, window.pending_think = "", ""
    if ok then
      require("agent.chat.session").charge(session, usage)
      session.turns = (session.turns or 0) + 1
      require("agent.chat.store").put(session)
    else
      require("utils.log").error(("Chat: %s"):format(err or "request failed"))
    end
    window.draw()
  end

  require("agent.chat.runner").run(sel, { system = system, prompt = prompt }, {
    on_text = function(delta)
      if not window.running then
        return
      end
      window.pending_text = window.pending_text .. delta
      draw_soon()
    end,
    on_think = function(delta)
      if not window.running then
        return
      end
      window.pending_think = window.pending_think .. delta
      draw_soon()
    end,
  }, function(ok, body, usage, err)
    -- cleanup owns the spinner + store; clear the flags here so draw never shows a stale stream
    window.pending_text, window.pending_think = "", ""
    -- keep the turn in the transcript even on failure (the error is visible)
    if ok then
      require("agent.chat.session").add(session, { role = "user", text = clean })
      require("agent.chat.session").add(
        session,
        { role = "assistant", text = body, usage = usage, meta = { injected = injected } }
      )
      if window.pending_think ~= "" then
        require("agent.chat.session").add(session, { role = "thinking", text = window.pending_think })
      end
    else
      require("agent.chat.session").add(session, { role = "user", text = clean })
      require("agent.chat.session").add(session, { role = "tool", text = ("⚠ %s"):format(err or "error") })
    end
    window.pending_text, window.pending_think = "", ""
    cleanup(ok, usage, err)
  end)
end

return M
