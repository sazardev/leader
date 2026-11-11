-- Chat facade (<leader>aC): a persistent, backend-agnostic chat under Leader.
-- Claude Code + Opencode shape (right half partition, streaming, thinking,
-- /commands, @files, #skills, $mcp, model + effort + profile pickers), but
-- Leader orchestrates: every turn is shown transparently (what was injected,
-- tokens, cost, time) and persisted per project. The history home scopes
-- sessions to the repository. Hiding the panel keeps the session; statusline shows it.
local M = {}

--- Root of the project the chat belongs to.
---@return string
local function project_root()
  return vim.fs.root(0, ".git") or (vim.uv.cwd() or "")
end

--- Fills a new session's backend/model/effort/profile from the current choice.
---@param session table
local function defaults(session)
  local sel = require("agent.selection").current()
  if sel then
    session.backend, session.model, session.effort = sel.backend, sel.model, sel.effort
  end
  session.profile = session.profile or require("core.settings").agent.chat.profile or "write"
end

--- The session the caller means. A draft (never written to disk until the
--- first message) instead of auto-resuming another project's chat.
---@return table
local function current()
  local window = require "agent.chat.window"
  if window.session then
    if window.session.profile == nil then
      window.session.profile = require("core.settings").agent.chat.profile or "write"
    end
    return window.session
  end
  local session = require("agent.chat.session").new { root = project_root() }
  defaults(session)
  window.session = session
  return session
end

--- Toggle the panel (open / hide). <leader>aC.
--- The first open in a project with history lands on that history: select a
--- conversation or type straight into the input to start a new one.
--- Already open but not focused: it comes forward instead of disappearing.
function M.open()
  local cfg = require("core.settings").agent.chat
  if not cfg.enabled then
    return require("utils.log").warn "Chat: disabled (settings.agent.chat.enabled = false)"
  end
  local window = require "agent.chat.window"
  local root = project_root()

  -- a chat belongs to its repository: opening the panel in another project
  -- shows that project's history, never the previous repo's conversation.
  -- Never detach a running turn from the session its stream belongs to.
  if not window.is_open() and not window.running then
    if (window.session and window.session.root ~= root) or (window.home and window.home.root ~= root) then
      window.session, window.home = nil, nil
    end
  end

  if window.is_open() then
    local cur = vim.api.nvim_get_current_win()
    if cur == window.input_win or cur == window.transcript_win then
      window.toggle() -- focused: hide
    else
      window.focus() -- open behind the code: bring it forward
    end
  else
    if not window.session and not window.home then
      local store = require "agent.chat.store"
      local sessions = store.list_for_root(root)
      if cfg.history_on_open ~= false and #sessions > 0 then
        window.show_home(root)
      else
        -- opt-out: resume the last chat of this repo (a repo with no history starts fresh)
        window.session = store.last_for_root(root) or current()
      end
    end
    window.toggle()
  end
  if not window.is_open() then
    require("utils.log").error "Chat: could not open the panel (:messages has the error)"
  end
end

--- Collapse to the right-edge rail (or expand again). <C-t> inside the panel.
function M.toggle_collapse()
  require("agent.chat.window").toggle_collapse()
end

--- Mini (right partition) or fullscreen. <C-f> inside the panel, :Chat full/mini.
---@param view "mini"|"full"
function M.set_view(view)
  local window = require "agent.chat.window"
  if not window.is_open() then
    window.view = view
    return
  end
  window.set_view(view)
end

--- Toggle mini <-> full.
function M.toggle_view()
  local window = require "agent.chat.window"
  if not window.is_open() then
    window.view = window.current_view() == "full" and "mini" or "full"
    return
  end
  window.toggle_view()
end

--- Start a fresh session in this project.
function M.new_session()
  local window = require "agent.chat.window"
  if window.running then
    return require("utils.log").warn "Chat: still answering (Ctrl-X stops it)"
  end
  local previous = window.session
  local session = require("agent.chat.session").new { root = project_root() }
  defaults(session)
  -- a new chat keeps the profile and model you were using
  if previous then
    session.profile = previous.profile or session.profile
    session.backend = previous.backend or session.backend
    session.model = previous.model or session.model
    session.effort = previous.effort or session.effort
  end
  -- an empty chat is not history: it is written on its first message
  window.session = session
  window.home = nil
  window.pending_text, window.pending_think, window.injected_names = "", "", nil
  if window.is_open() then
    window.draw()
    window.refresh_placeholder()
  else
    window.toggle()
  end
  -- focus the input
  if window.input_win then
    vim.api.nvim_set_current_win(window.input_win)
    vim.cmd "startinsert"
  end
end

--- The project's chat history: the panel home, not a floating picker. A fresh
--- open lands here by itself when the repo already has conversations.
function M.pick_session()
  local window = require "agent.chat.window"
  local root = project_root()
  window.show_home(root)
  if not window.is_open() then
    window.toggle()
  else
    window.focus()
  end
  window.refresh_placeholder()
end

--- Pick the profile of this chat: ask (read-only), write (code) or minimal.
function M.pick_profile()
  local session = current()
  local window = require "agent.chat.window"
  local profiles = require "agent.chat.profiles"
  local items = {}
  for _, profile in ipairs(profiles.list()) do
    items[#items + 1] = {
      label = ("%-8s %s · %s"):format(profile.label, profile.description, profile.hint),
      id = profile.id,
      current = session.profile == profile.id,
    }
  end
  require("agent.ui.select").pick(items, { title = "Chat · profile" }, function(choice)
    session.profile = choice.id
    if #(session.messages or {}) > 0 then
      require("agent.chat.store").put(session)
    end
    if window.home then
      window.home.profile = choice.id
    end
    window.draw()
    window.refresh_placeholder()
    require("utils.log").info(("Chat: %s profile"):format(choice.id))
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
      if #(session.messages or {}) > 0 then
        require("agent.chat.store").put(session)
      end
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
    if #(session.messages or {}) > 0 then
      require("agent.chat.store").put(session)
    end
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
  if require("agent.chat.window").running then
    return require("utils.log").warn "Chat: still answering (Ctrl-X stops it)"
  end
  local session = current()
  local had = #(session.messages or {}) > 0
  session.messages = {}
  session.tokens_in, session.tokens_out, session.cost, session.turns = 0, 0, 0, 0
  if had then
    require("agent.chat.store").put(session)
  end
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

--- Show help (only on demand: the chrome shows just "Enter send").
function M.help()
  local lines = {
    "Leader Chat — help",
    "",
    "Profiles: Ask (read-only) · Write (code and plans) · Minimal (fast, no auto context). Ctrl-P or /profile.",
    "History: Ctrl-H or /history. On the home: Up/Down select, Enter open, n new, D delete. Typing starts a new chat.",
    "Send: Enter · New line: Shift-Enter · Hide: Ctrl-Q (the session keeps running).",
    "Triggers, filtered as you type (Enter/Tab accepts): / commands · @ project files (@buf, @sel, @diag) · # skills · $ MCP.",
    "Commands: /new · /history · /model · /effort · /profile · /clear · /adr · /export · /full · /mini · /collapse · /help.",
    "Input: Up/Down previous messages · Shift-Enter new line · it grows with the text.",
    "View: Ctrl-F (half/full) · Ctrl-T (collapse to rail).",
    "Keys: Ctrl-N new · Ctrl-H history · Ctrl-M model · Ctrl-E effort · Ctrl-P profile · Ctrl-A ADR · Ctrl-X stop.",
    "Transcript: y copy message · c copy its code block · Y copy all · o view message · h history · i input · A apply its files · Ctrl-Q hide.",
    "Copy from anywhere (composer included): Ctrl-Y the last answer · Alt-Y your last message.",
    "Questions: a fenced ask block lists options; Alt-Q picks one into the composer (it is never sent for you).",
    "Typing while it answers queues the message: it is sent when the turn settles.",
    "Context: an answer's `@need: path` is injected on the next turn; a long chat says how much history was left out.",
    "Write mode applies full files returned as ```lang: path blocks to existing project files (toggle: settings.agent.chat.apply).",
  }
  require("agent.ui.panel").open(lines, "Leader Chat · help")
end

--- Send one user turn: parse mentions, collect context, run a turn.
--- `Enter` sends with whatever is already selected (session > <leader>am > the
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

  -- Slash commands first: they do not need a backend, a session or context.
  local command = raw:match "^%s*/(%w+)"
  if command and require("agent.chat.commands").has(command) then
    if command == "new" then
      M.new_session()
    elseif command == "history" then
      M.pick_session()
    elseif command == "clear" then
      M.clear()
    elseif command == "model" then
      M.pick_model()
    elseif command == "effort" then
      M.pick_effort()
    elseif command == "profile" then
      M.pick_profile()
    elseif command == "adr" then
      M.draft_adr()
    elseif command == "export" then
      M.export()
    elseif command == "collapse" then
      M.toggle_collapse()
    elseif command == "full" then
      M.set_view "full"
    elseif command == "mini" then
      M.set_view "mini"
    elseif command == "help" then
      M.help()
    end
    return true
  end

  -- Typing while the answer streams queues the message instead of losing it:
  -- it is sent as soon as the turn settles. A slash command above still runs.
  if window.running then
    window.enqueue(raw)
    return true
  end

  -- From the history home, a message starts a new chat. It inherits the profile
  -- and model of the draft that was there (or of the global selection).
  local session = window.session
  if window.home then
    local previous = session
    session = require("agent.chat.session").new { root = window.home.root }
    defaults(session)
    if previous then
      session.profile = previous.profile or session.profile
      if #(previous.messages or {}) == 0 then
        session.backend = previous.backend or session.backend
        session.model = previous.model or session.model
        session.effort = previous.effort or session.effort
      end
    else
      session.profile = window.home.profile or session.profile
    end
    window.home, window.session = nil, session
    window.draw()
    window.refresh_placeholder()
  elseif not session then
    session = current()
  end

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
  local profile = require("agent.chat.profiles").of(session, require("core.settings").agent.chat.profile)

  local function turn(choice)
    local clean, mentions = require("agent.chat.mention").parse(raw)
    if clean == "" and #mentions == 0 then
      return
    end

    -- auto context (what Leader injects besides the messages); a broken provider
    -- must not kill the turn (agent/context lets providers fail the same way).
    -- The profile decides what is injected: minimal gets only the mentions.
    local auto = {}
    local ok_auto, got = pcall(require("agent.chat.context").collect, profile)
    if ok_auto and got then
      auto = got
    elseif not ok_auto then
      require("utils.log").warn(("Chat: context skipped: %s"):format(tostring(got):sub(1, 160)))
    end
    local need_sections = require("agent.chat.needs").collect(session)
    local sections = vim.list_extend({}, mentions)
    -- files the previous answer requested with @need: (injected exactly once)
    vim.list_extend(sections, need_sections)
    vim.list_extend(sections, type(auto) == "table" and auto or {})
    -- one section per name: the same file mentioned and requested is one file
    local seen, unique = {}, {}
    for _, section in ipairs(sections) do
      if not seen[section.name] then
        seen[section.name] = true
        unique[#unique + 1] = section
      end
    end
    sections = unique
    window.injected_names = vim.tbl_map(function(s)
      return s.name
    end, sections)

    local system, prompt, injected, dropped = require("agent.chat.prompt").build(session, clean, sections, profile)
    if dropped > 0 and not session.history_warned then
      session.history_warned = true
      require("utils.log").warn(
        ("Chat: long chat — the oldest %s chars are not sent"):format(require("agent.chat.text").tokens(dropped))
      )
    end

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
      if #need_sections > 0 then
        require("agent.chat.needs").mark(session)
      end
      window.clear_input()
      window.sent_text = clean
      -- the first real message is what puts a chat in the history
      require("agent.chat.store").put(session)
      M._launch(session, choice, clean, system, prompt, injected, profile.id, dropped)
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
---@param profile string? profile id used for the turn
---@param dropped integer? chars of history left out (the footer says so)
function M._launch(session, sel, clean, system, prompt, injected, profile, dropped)
  if profile then
    session.profile = profile
  end
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
    else
      require("utils.log").error(("Chat: %s"):format(err or "request failed"))
    end
    require("agent.chat.store").put(session)
    window.draw()
    -- the answer landed while the user was elsewhere: one note, never a modal
    if ok then
      window.notify_ready(session)
      if require("agent.chat.ask").of(session) and window.can_auto_ask() then
        vim.schedule(function()
          window.answer_question()
        end)
      end
    end
    -- a message typed while this turn ran goes now, in order
    local next_text = window.dequeue()
    if next_text then
      vim.schedule(function()
        local accepted = require("agent.chat").send(next_text)
        if not accepted then
          window.set_input(next_text) -- never lose it: back in the composer
        end
      end)
    end
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
    -- capture the reasoning before clearing the live stream; it belongs to the transcript
    local thinking = window.pending_think
    window.pending_text, window.pending_think = "", ""
    -- keep the turn in the transcript even on failure (the error is visible)
    require("agent.chat.session").add(session, { role = "user", text = clean })
    local applied = { files = {}, unchanged = {}, skipped = {}, errors = {} }
    if ok and (session.profile or "write") == "write" and require("core.settings").agent.chat.apply ~= false then
      applied = require("agent.chat.apply").run(session, body)
      if #applied.files > 0 then
        require("utils.log").info(("Chat: applied %s"):format(table.concat(applied.files, ", ")))
      end
      if #applied.errors > 0 then
        require("utils.log").warn(("Chat: not applied %s"):format(table.concat(applied.errors, "; ")))
      end
    end
    if ok then
      require("agent.chat.session").add(session, {
        role = "assistant",
        text = body,
        usage = usage,
        meta = {
          injected = injected,
          applied = applied.files,
          apply_unchanged = applied.unchanged,
          apply_skipped = applied.skipped,
          apply_errors = applied.errors,
          history_dropped = dropped,
        },
      })
      if thinking and thinking ~= "" then
        require("agent.chat.session").add(session, { role = "thinking", text = thinking })
      end
    else
      require("agent.chat.session").add(session, { role = "tool", text = ("error: %s"):format(err or "error") })
    end
    window.injected_names = nil
    cleanup(ok, usage, err)
  end)
end

return M
