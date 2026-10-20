-- ── Desktop app: the guided setup ────────────────────────────────────────────
-- What the first launch opens (and Ctrl+Shift+W, the bar's "to finish" chip or
-- Help › Welcome later). One full-screen page (the statusline and the tabline step
-- aside while it is open), laid out once for the window so nothing ever scrolls:
--   top     the steps (✓ done · the current one lit · ○ ahead; done ones clickable)
--           the step's title and one line that says what to do
--   middle  the choices, in columns when they do not fit one
--   bottom  what is missing to go on (or ✓ ready), the buttons (← Back on the
--           left, Next → on the right, always in the same place) and the keys
-- A step lets you go on only when it is done (a theme picked, a language, an agent
-- or "no agent", the installs done or skipped): Next stays off and says why.
-- Keys: arrows (or j/k/h/l) move, Space chooses, Enter chooses and then goes on,
-- Backspace goes back, Tab jumps to the buttons, q leaves. The mouse: the choice
-- under the pointer lights up, a click chooses, the buttons and the steps click.
-- Choices apply as they are made and are saved where the settings panel saves
-- them (prefs/store.lua), so <leader>Sp can change them later.
local mouse = require "utils.mouse"
local state = require "gui.state"
local sysdeps = require "gui.sysdeps"

local M = {}

M.STEPS = {
  { id = "welcome", title = "Welcome" },
  { id = "theme", title = "Theme" },
  { id = "languages", title = "Languages" },
  { id = "features", title = "Features" },
  { id = "window", title = "Window" },
  { id = "agent", title = "Agent" },
  { id = "install", title = "Install" },
  { id = "review", title = "Review" },
}

--- The settings worth deciding on day one (prefs ids), with what each one does in a line.
M.FEATURES = {
  { id = "format_on_save.enabled", desc = "formats a file when you save it" },
  { id = "ui.motion", desc = "floats and menus fade in" },
  { id = "ui.blink_cursor", desc = "a blinking cursor" },
  { id = "ui.keys", desc = "shows the keys you press (for demos)" },
  { id = "history.word_undo", desc = "u undoes one word at a time" },
  { id = "clipboard.keep", desc = "x and c keep what you copied" },
  { id = "session.autosave_ms", desc = "how often your session is saved" },
  { id = "agent.verify.enabled", desc = "checks code after an agent's change" },
  { id = "agent.budget.enabled", desc = "asks before an expensive request" },
  { id = "light.force", desc = "no resident language servers (old PCs)" },
}

--- How to install each agent that can be installed from here (the Install step offers it).
M.AGENT_INSTALL = {
  claude = { label = "Claude Code", cmd = "npm install -g @anthropic-ai/claude-code" },
  opencode = { label = "OpenCode", cmd = "npm install -g opencode-ai" },
  ollama = { label = "Ollama (local models)", cmd = "curl -fsSL https://ollama.com/install.sh | sh" },
}

local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local NS = vim.api.nvim_create_namespace "GuiWizard"

local function exe(bin)
  return vim.fn.executable(bin) == 1
end

local function width_of(s)
  return vim.fn.strdisplaywidth(s)
end

local function cut(s, w)
  if width_of(s) <= w then
    return s
  end
  return vim.fn.strcharpart(s, 0, math.max(w - 1, 0)) .. "…"
end

local function pad(s, w)
  return s .. string.rep(" ", math.max(w - width_of(s), 0))
end

-- ── what the steps read ────────────────────────────────────────────────────

---@param w table
---@return table<string, boolean> pack id → on (as chosen in this setup)
local function packs_now(w)
  if w.packs then
    return w.packs
  end
  local out = {}
  local languages = require "languages"
  for _, p in ipairs(require("languages.packs").packs) do
    local on = false
    for _, name in ipairs(p.langs) do
      on = on or not languages.disabled(name)
    end
    out[p.id] = on
  end
  w.packs, w.packs_before = out, vim.deepcopy(out)
  return out
end

---@param w table
local function system(w)
  if w.sys then
    return w.sys
  end
  local f = io.open "/etc/os-release"
  local release = f and f:read "*a" or nil
  if f then
    f:close()
  end
  w.sys = {
    distro = sysdeps.distro(release) or vim.uv.os_uname().sysname,
    manager = sysdeps.manager(exe),
    root = vim.uv.getuid and vim.uv.getuid() == 0 or false,
    wsl = vim.fn.has "wsl" == 1,
  }
  return w.sys
end

--- The agents found here and their models (asked once per opening).
---@param w table
local function agents(w)
  if w.agents then
    return w.agents
  end
  local out = {}
  local ok, backends = pcall(require, "agent.backends")
  if ok then
    for _, name in ipairs(backends.names()) do
      local b = backends.get(name)
      local entry = { name = name, available = b ~= nil and backends.is_available(name), models = {} }
      if entry.available then
        local done = false
        pcall(b.models, function(list)
          entry.models = vim.tbl_map(function(x)
            return x.id or x.name or tostring(x)
          end, list or {})
          done = true
        end)
        vim.wait(800, function()
          return done
        end, 20)
      end
      out[#out + 1] = entry
    end
  end
  w.agents = out
  return out
end

--- What the Install step offers: missing system tools, Leader's own pieces, the agents you asked for.
---@param w table
local function plan(w)
  if w.plan then
    return w.plan
  end
  local sys = system(w)
  local items = {}
  for _, t in ipairs(sysdeps.missing(exe, packs_now(w))) do
    items[#items + 1] = { kind = "sys", tool = t, label = t.label, desc = t.why, on = true, status = "todo" }
  end
  for _, c in ipairs(require("gui.checks").run()) do
    if not c.ok and c.fix then
      items[#items + 1] =
        { kind = "leader", check = c.id, label = c.label, desc = c.detail, fix = c.fix, on = true, status = "todo" }
    end
  end
  for name, want in pairs(w.agent_install or {}) do
    local spec = M.AGENT_INSTALL[name]
    if want and spec then
      items[#items + 1] = {
        kind = "agent",
        backend = name,
        label = spec.label,
        desc = spec.cmd,
        cmd = spec.cmd,
        on = true,
        status = "todo",
      }
    end
  end
  w.plan = { items = items, sys = sys }
  return w.plan
end

---@param w table
---@return string? the one shell line for the checked system tools and agent installers
function M.system_command(w)
  local pl = plan(w)
  local tools, extra = {}, {}
  for _, it in ipairs(pl.items) do
    if it.on and it.status ~= "done" and it.kind == "sys" then
      tools[#tools + 1] = it.tool
    elseif it.on and it.status ~= "done" and it.kind == "agent" then
      extra[#extra + 1] = it.cmd
    end
  end
  local cmds = {}
  if #tools > 0 and pl.sys.manager then
    cmds[#cmds + 1] = sysdeps.command(pl.sys.manager, tools, pl.sys.root)
  end
  vim.list_extend(cmds, extra)
  return #cmds > 0 and table.concat(cmds, " && ") or nil
end

---@param w table
---@return integer checked items not installed yet
local function pending(w)
  return #vim.tbl_filter(function(it)
    return it.on and it.status ~= "done"
  end, plan(w).items)
end

-- ── the steps ──────────────────────────────────────────────────────────────
-- Each step: title, guide (one line: what to do), `info(w)` lines above the choices, `items(w)` the choices,
-- `ready(w)` → ok, what is missing, and optionally `buttons(w)` instead of Back · Next.

---@class WizardItem
---@field group string?  a header above it (when the group changes)
---@field label string
---@field desc string?
---@field mark "radio"|"check"|"value"|"action"|"status"
---@field on boolean?
---@field value string?  for "value": what the setting is now
---@field status string? for "status": todo · running · done · failed
---@field choose fun(w: table)?
---@field focus fun(w: table)?  runs when it gets the focus (a theme previews)

local STEP = {}

STEP.welcome = {
  title = "Welcome to Leader",
  guide = "Seven short steps to make the editor yours. Nothing is installed without asking. Enter to begin.",
  info = function(w)
    local sys = system(w)
    local v = vim.version()
    local rows = {
      { "System", sys.distro .. (sys.wsl and "  ·  WSL" or "") },
      {
        "Packages",
        sys.manager and (sys.manager.id .. "  (" .. sys.manager.family .. ")") or "no package manager found",
      },
      { "GPU", ((vim.g.leader_gui_gpu or "starting…"):gsub(",.*$", "")) },
      { "Neovim", ("%d.%d.%d"):format(v.major, v.minor, v.patch) },
      { "App", vim.g.leader_gui_version or "?" },
    }
    local out = {}
    for _, r in ipairs(rows) do
      out[#out + 1] = { { pad(r[1], 12), "GuiPickerLabel" }, { r[2], "GuiPickerText" } }
    end
    out[#out + 1] = { { "" } }
    out[#out + 1] =
      { { "Next: a theme, your languages, a few features, an agent, what to install, a review.", "GuiPickerDim" } }
    return out
  end,
  items = function()
    return {}
  end,
  ready = function()
    return true
  end,
}

STEP.theme = {
  title = "Pick a look",
  guide = "Move over a theme to see it on the whole editor. Space or a click picks it.",
  items = function(w)
    local appearance = require "appearance"
    local themes = require("gui").THEMES
    local items = {}
    for _, group in ipairs { { "DARK", themes.dark }, { "LIGHT", themes.light } } do
      for _, name in ipairs(group[2]) do
        if #vim.api.nvim_get_runtime_file("lua/base46/themes/" .. name .. ".lua", false) > 0 then
          items[#items + 1] = {
            group = group[1],
            label = name,
            mark = "radio",
            on = w.theme == name,
            choose = function()
              w.theme = name
              pcall(appearance.use, name)
            end,
            focus = function()
              pcall(appearance.use, name)
            end,
          }
        end
      end
    end
    items[#items + 1] = {
      group = "YOUR TERMINAL",
      label = "terminal",
      desc = "its own palette",
      mark = "radio",
      on = w.theme == appearance.TERMINAL,
      choose = function()
        w.theme = appearance.TERMINAL
        pcall(appearance.use, appearance.TERMINAL)
      end,
      focus = function()
        pcall(appearance.use, appearance.TERMINAL)
      end,
    }
    return items
  end,
  ready = function(w)
    return w.theme ~= nil, "Pick a theme to continue"
  end,
  done = function(w)
    return "Theme: " .. w.theme
  end,
}

STEP.languages = {
  title = "Your languages",
  guide = "Check the ones you work with: they get their language servers, formatters and linters. Already checked: what this machine uses.",
  items = function(w)
    local packs = packs_now(w)
    local items = {}
    for _, pk in ipairs(require("languages.packs").packs) do
      local found = vim.tbl_filter(exe, pk.detect)
      items[#items + 1] = {
        label = pk.label,
        desc = #found > 0 and ("found: " .. table.concat(found, ", ")) or nil,
        mark = "check",
        on = packs[pk.id],
        choose = function()
          packs[pk.id] = not packs[pk.id]
          w.basics = false
        end,
      }
    end
    items[#items + 1] = {
      group = "OR",
      label = "Only the basics",
      desc = "Lua, Markdown, JSON, YAML, TOML",
      mark = "radio",
      on = w.basics == true,
      choose = function()
        for id in pairs(packs) do
          packs[id] = false
        end
        w.basics = true
      end,
    }
    return items
  end,
  ready = function(w)
    local any = vim.iter(packs_now(w)):any(function(_, on)
      return on
    end)
    return any or w.basics == true, "Check at least one language, or Only the basics"
  end,
  done = function(w)
    local changed = w.packs_before and not vim.deep_equal(packs_now(w), w.packs_before)
    return changed and "New languages start after a restart (offered at the end)" or "Languages set"
  end,
}

STEP.features = {
  title = "A few features",
  guide = "Each one is ready as it is. Space or a click changes it; the settings panel has the rest.",
  items = function()
    local prefs = require "prefs"
    local items = {}
    for _, f in ipairs(M.FEATURES) do
      local item = prefs.find(f.id)
      if item then
        local value = prefs.text(item)
        items[#items + 1] = {
          label = item.label,
          desc = f.desc,
          mark = "value",
          value = value,
          on = value ~= "off" and value ~= "only on exit",
          choose = function()
            prefs.cycle(item)
          end,
        }
      end
    end
    return items
  end,
  ready = function()
    return true
  end,
}

--- Where a step is in M.STEPS.
---@param id string
---@return integer
function M.index(id)
  for i, s in ipairs(M.STEPS) do
    if s.id == id then
      return i
    end
  end
  return 1
end

STEP.window = {
  title = "Window and start",
  guide = "What Leader opens when it starts, its frame, and what it keeps of the window when it closes.",
  items = function()
    local prefs = require "prefs"
    local items = {}
    local function radio(group, id, value, label, desc)
      local item = prefs.find(id)
      if item then
        items[#items + 1] = {
          group = group,
          label = label,
          desc = desc,
          mark = "radio",
          on = prefs.value(item) == value,
          choose = function()
            prefs.set(item, value)
          end,
        }
      end
    end
    radio("ON START", "gui.window.on_start", "ask", "Ask which project", "the project picker, like an IDE")
    radio("ON START", "gui.window.on_start", "last", "The last project", "straight back to where you were")
    radio("ON START", "gui.window.on_start", "home", "The start screen", "recent files and the menu")
    radio("FRAME", "gui.appbar.enabled", true, "Leader's own, square", "the bar with the path and the tools")
    radio("FRAME", "gui.appbar.enabled", false, "The system's, bordered", "your desktop's title bar")
    local placed = vim.g.leader_gui_can_position ~= false
    for _, r in ipairs {
      { "gui.window.remember_size", "Its size" },
      { "gui.window.remember_position", "Where it was", not placed and "not on Wayland: the system places windows" },
      { "gui.window.remember_maximized", "Being maximized" },
    } do
      local item = prefs.find(r[1])
      if item then
        items[#items + 1] = {
          group = "REMEMBER",
          label = r[2],
          desc = r[3] or nil,
          mark = "check",
          on = prefs.value(item) ~= false,
          choose = function()
            prefs.cycle(item)
          end,
        }
      end
    end
    return items
  end,
  ready = function()
    return true
  end,
}

STEP.agent = {
  title = "An AI agent",
  guide = "The inline agent (Space a) explains, fixes and writes code. Pick a model, or go on without one.",
  items = function(w)
    local selection = require "agent.selection"
    w.agent_install = w.agent_install or {}
    local items = {}
    for _, a in ipairs(agents(w)) do
      if a.available then
        for _, model in ipairs(a.models) do
          items[#items + 1] = {
            group = a.name:upper(),
            label = model,
            mark = "radio",
            on = w.agent == a.name .. "/" .. model,
            choose = function()
              selection.set(a.name, model)
              w.agent = a.name .. "/" .. model
              require("gui").update()
            end,
          }
        end
      end
    end
    for _, a in ipairs(agents(w)) do
      if not a.available and M.AGENT_INSTALL[a.name] then
        items[#items + 1] = {
          group = "TO INSTALL",
          label = M.AGENT_INSTALL[a.name].label,
          desc = "in the next step",
          mark = "check",
          on = w.agent_install[a.name] == true,
          choose = function()
            w.agent_install[a.name] = not w.agent_install[a.name]
            if w.agent_install[a.name] then
              w.agent = w.agent or ("install " .. a.name)
            end
          end,
        }
      end
    end
    items[#items + 1] = {
      group = "OR",
      label = "No agent for now",
      desc = "add one later: Space a m",
      mark = "radio",
      on = w.agent == "none",
      choose = function()
        w.agent = "none"
      end,
    }
    return items
  end,
  ready = function(w)
    return w.agent ~= nil, "Pick a model, one to install, or No agent for now"
  end,
  done = function(w)
    return w.agent == "none" and "No agent for now" or ("Agent: " .. w.agent)
  end,
}

local STATUS = {
  todo = { "", "GuiPickerDim" },
  done = { "✓ done", "GuiWizardOn" },
  failed = { "✗ failed", "GuiWizardBad" },
  ok = { "✓ ok", "GuiWizardOn" },
  missing = { "! missing", "GuiWizardKey" },
}

STEP.install = {
  title = "What to install",
  guide = "What Leader still needs here. Uncheck what you do not want; nothing runs until you press Install.",
  info = function(w, width)
    -- the language tools while Mason works on them (and the result after): every tool, its numbers, the time
    local tracker = require("gui.progress").current
    if tracker and (tracker.active or w.progress_seen) then
      w.progress_seen = true
      local spin = SPIN[(w.spin or 0) % #SPIN + 1]
      local out = { { { "" } } }
      vim.list_extend(out, require("gui.progress").lines(tracker, os.time(), width, spin))
      out[#out + 1] = { { "" } }
      return out
    end
    local cmd = M.system_command(w)
    if not cmd then
      return {}
    end
    local out = { { { "This runs in a terminal (sudo asks for your password there):", "GuiPickerLabel" } } }
    for _, l in ipairs(require("utils.market").wrap(cmd, width - 4)) do
      out[#out + 1] = { { "$ " .. l, "GuiWizardCode" } }
    end
    out[#out + 1] = { { "" } }
    return out
  end,
  items = function(w)
    local pl = plan(w)
    local items = {}
    local titles = {
      sys = "SYSTEM  ·  " .. pl.sys.distro .. (pl.sys.manager and ("  ·  " .. pl.sys.manager.id) or ""),
      leader = "LEADER",
      agent = "AGENTS",
    }
    for _, it in ipairs(pl.items) do
      items[#items + 1] = {
        group = titles[it.kind],
        label = it.label,
        desc = it.desc,
        mark = "status",
        on = it.on,
        status = it.status,
        choose = function()
          if it.status == "todo" or it.status == "failed" then
            it.on = not it.on
          end
        end,
      }
    end
    if #items == 0 then
      items[1] = { label = "Everything is installed", mark = "action", desc = "nothing to do here" }
    end
    return items
  end,
  ready = function(w)
    if #plan(w).items == 0 or w.install_skipped then
      return true
    end
    local tracker = require("gui.progress").current
    if w.running or (tracker and tracker.active) then
      local s = tracker and require("gui.progress").summary(tracker, os.time())
      return false,
        s and ("Installing language tools: %d of %d, %s so far"):format(
          s.done + s.failed,
          s.total,
          require("gui.progress").dur(s.elapsed)
        ) or "Installing…"
    end
    return pending(w) == 0, "Install the checked items, or Skip for now"
  end,
  done = function(w)
    return w.install_skipped and "Skipped: the bar's chip brings it back" or "Installed"
  end,
  buttons = function(w)
    if #plan(w).items == 0 then
      return nil
    end
    local n = pending(w)
    local out = {}
    local tracker = require("gui.progress").current
    local busy = w.running or (tracker and tracker.active)
    if n > 0 and not busy then
      out[#out + 1] = {
        label = "Skip for now",
        press = function()
          w.install_skipped = true
          M.go(w, w.step + 1)
        end,
      }
      out[#out + 1] = {
        label = ("Install  (%d)"):format(n),
        primary = true,
        press = function()
          M.install(w)
        end,
      }
    elseif busy then
      out[#out + 1] = { label = SPIN[(w.spin or 0) % #SPIN + 1] .. "  Installing…", primary = true, off = true }
    end
    return out
  end,
}

STEP.review = {
  title = "All set",
  guide = "What you chose and how this machine looks now. Finish closes this; Space S p changes anything later.",
  info = function(w, width)
    local appearance = require "appearance"
    local selection = require "agent.selection"
    local cur = selection.current()
    local on = {}
    for _, pk in ipairs(require("languages.packs").packs) do
      if packs_now(w)[pk.id] then
        on[#on + 1] = (pk.label:gsub(":.*$", ""))
      end
    end
    local out = {}
    for _, f in ipairs {
      { "Theme", appearance.current() },
      { "Languages", #on > 0 and table.concat(on, ", ") or "the basics" },
      { "Agent", cur and selection.label(cur) or "none" },
    } do
      out[#out + 1] = { { pad(f[1], 12), "GuiPickerLabel" }, { cut(f[2], width - 14), "GuiPickerText" } }
    end
    out[#out + 1] = { { "" } }
    return out
  end,
  items = function(w)
    local items = {}
    for _, c in ipairs(w.checks or require("gui.checks").run()) do
      items[#items + 1] = {
        group = "THIS MACHINE",
        label = c.label,
        desc = c.detail,
        mark = "status",
        on = true,
        status = c.ok and "ok" or "missing",
        choose = not c.ok and function()
          M.go(w, M.index "install")
        end or nil,
      }
    end
    return items
  end,
  ready = function()
    return true
  end,
  buttons = function(w)
    local out = {}
    if w.packs_before and not vim.deep_equal(packs_now(w), w.packs_before) then
      out[#out + 1] = {
        label = "Restart Leader",
        press = function()
          M.finish(w)
          if vim.g.leader_gui_channel then
            vim.rpcnotify(vim.g.leader_gui_channel, "leader_window", "restart:" .. (vim.uv.cwd() or ""))
          end
        end,
      }
    end
    out[#out + 1] = {
      label = "Open a project…",
      press = function()
        M.finish(w)
        require("gui.picker").open()
      end,
    }
    out[#out + 1] = {
      label = "Finish  ✓",
      primary = true,
      press = function()
        M.finish(w)
      end,
    }
    return out
  end,
}

-- ── drawing ────────────────────────────────────────────────────────────────
-- A canvas: positioned segments per row (display columns), composed into the buffer with their highlights; every
-- clickable thing leaves a region (row, columns) → what it does.

local function canvas(rows)
  local c = { rows = {}, regions = {}, fills = {} }
  for r = 1, rows do
    c.rows[r] = {}
  end
  --- A background under whatever text sits there (the focused choice): painted under the text, not in its place.
  function c.fill(r, col, w, hl, hit)
    c.fills[#c.fills + 1] = { row = r, from = col, to = col + w, hl = hl }
    if hit then
      c.regions[#c.regions + 1] = { row = r, from = col, to = col + w, hit = hit }
    end
  end
  function c.put(r, col, text, hl, hit)
    if r < 1 or r > rows or text == "" then
      return col
    end
    table.insert(c.rows[r], { col = col, text = text, hl = hl })
    local w = width_of(text)
    if hit then
      c.regions[#c.regions + 1] = { row = r, from = col, to = col + w, hit = hit }
    end
    return col + w
  end
  function c.flush(buf)
    local lines, marks = {}, {}
    local reach = {}
    for _, f in ipairs(c.fills) do
      reach[f.row] = math.max(reach[f.row] or 0, f.to)
    end
    local maps = {}
    for r, segs in ipairs(c.rows) do
      table.sort(segs, function(a, b)
        return a.col < b.col
      end)
      local parts, col, bytes = {}, 0, 0
      -- display column → byte, at every column the row has (for the fills)
      local map = {}
      local function spaces(n)
        for i = 0, n - 1 do
          map[col + i] = bytes + i
        end
        local gap = string.rep(" ", n)
        parts[#parts + 1] = gap
        bytes = bytes + n
        col = col + n
      end
      for _, s in ipairs(segs) do
        if s.col > col then
          spaces(s.col - col)
        end
        if s.hl then
          marks[#marks + 1] = { r - 1, bytes, bytes + #s.text, s.hl, 100 }
        end
        for _, ch in ipairs(vim.fn.split(s.text, "\\zs")) do
          for i = 0, width_of(ch) - 1 do
            map[col + i] = bytes
          end
          bytes = bytes + #ch
          col = col + width_of(ch)
        end
        parts[#parts + 1] = s.text
      end
      if reach[r] and reach[r] > col then
        spaces(reach[r] - col)
      end
      map[col] = bytes
      maps[r] = map
      lines[r] = table.concat(parts)
    end
    for _, f in ipairs(c.fills) do
      local map = maps[f.row]
      if map and map[f.from] and map[f.to] then
        marks[#marks + 1] = { f.row - 1, map[f.from], map[f.to], f.hl, 50 }
      end
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    for _, m in ipairs(marks) do
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, m[1], m[2], { end_col = m[3], hl_group = m[4], priority = m[5] })
    end
  end
  return c
end

local MARK = {
  radio = function(on)
    return on and "●" or "○", on and "GuiWizardOn" or "GuiWizardOff"
  end,
  check = function(on)
    return on and "■" or "□", on and "GuiWizardOn" or "GuiWizardOff"
  end,
}

--- Lays out and draws the whole page for the window's size (pure over `w` but for the buffer it writes).
---@param w table
function M.draw(w)
  if not (w.win and vim.api.nvim_win_is_valid(w.win)) then
    return
  end
  local W, H = vim.api.nvim_win_get_width(w.win), vim.api.nvim_win_get_height(w.win)
  local CW = math.min(W - 6, 104)
  local L = math.floor((W - CW) / 2)
  local c = canvas(H)
  local step = STEP[M.STEPS[w.step].id]
  w.reached = math.max(w.reached or 1, w.step)

  -- the steps across the top: done (clickable), the current one lit, the ones ahead dimmed
  -- (too narrow for every title: the others keep only their number)
  local parts, total, sep
  for _, short in ipairs { false, true } do
    parts, total, sep = {}, 0, short and " ─ " or "  ─  "
    for i, s in ipairs(M.STEPS) do
      local mark = w.done[i] and "✓ " or "○ "
      parts[i] = i == w.step and (" " .. i .. "  " .. s.title .. " ") or (mark .. (short and tostring(i) or s.title))
      total = total + width_of(parts[i]) + (i > 1 and width_of(sep) or 0)
    end
    if total <= CW then
      break
    end
  end
  local x = L + math.max(math.floor((CW - total) / 2), 0)
  for i, label in ipairs(parts) do
    if i > 1 then
      x = c.put(2, x, sep, "GuiWizardRule")
    end
    local hl = i == w.step and "GuiWizardStepNow" or w.done[i] and "GuiWizardStepDone" or "GuiWizardStepTodo"
    x = c.put(2, x, label, hl, i <= w.reached and i ~= w.step and { kind = "step", step = i } or nil)
  end
  c.put(4, L, string.rep("─", CW), "GuiWizardRule")

  -- title and what to do
  c.put(6, L, step.title, "GuiPickerTitle")
  local guide = require("utils.market").wrap(step.guide, CW)
  for i, l in ipairs(guide) do
    c.put(6 + i, L, l, "GuiPickerDim")
  end

  -- the bottom, fixed: a rule, what is missing (or ready), the buttons, the keys
  local keys_row, buttons_row, status_row, rule_row = H - 1, H - 3, H - 5, H - 6
  c.put(rule_row, L, string.rep("─", CW), "GuiWizardRule")
  local ok, why = step.ready(w)
  local last = w.step == #M.STEPS
  if ok then
    local text = step.done and step.done(w) or "Ready"
    c.put(
      status_row,
      L,
      "✓  " .. text .. "  ·  " .. (last and "Enter or Finish closes this" or "Enter or Next goes on"),
      "GuiWizardOn"
    )
  else
    c.put(status_row, L, "●  " .. (why or "Make a choice to continue"), "GuiWizardKey")
  end
  local buttons = step.buttons and step.buttons(w) or nil
  if not buttons then
    buttons = {}
  end
  if not last and not vim.iter(buttons):any(function(b)
    return b.primary
  end) then
    buttons[#buttons + 1] = {
      label = "Next  →",
      primary = true,
      off = not ok,
      press = function()
        M.next(w)
      end,
    }
  end
  if w.step > 1 then
    table.insert(buttons, 1, {
      label = "←  Back",
      left = true,
      press = function()
        M.go(w, w.step - 1)
      end,
    })
  end
  w.buttons = buttons
  -- the right ones from the right edge, Back on the left
  local rx = L + CW
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    if not b.left then
      local text = "  " .. b.label .. "  "
      rx = rx - width_of(text)
      local focused = w.area == "buttons" and w.bfocus == i
      local hl = b.off and "GuiWizardButtonOff" or (b.primary or focused) and "GuiWizardButton" or "GuiWizardButtonSoft"
      c.put(buttons_row, rx, text, hl, not b.off and { kind = "button", index = i } or nil)
      rx = rx - 2
    end
  end
  for i, b in ipairs(buttons) do
    if b.left then
      local focused = w.area == "buttons" and w.bfocus == i
      c.put(
        buttons_row,
        L,
        "  " .. b.label .. "  ",
        focused and "GuiWizardButton" or "GuiWizardButtonSoft",
        { kind = "button", index = i }
      )
    end
  end
  local keys = "↑↓←→ move   Space choose   Enter choose / next   Backspace back   Tab buttons   Esc leave"
  if width_of(keys) > CW then
    keys = "↑↓←→ move  Space choose  Enter next  ⌫ back  Tab buttons  Esc leave"
  end
  c.put(keys_row, L, cut(keys, CW), "GuiPickerLabel")

  -- the middle: info lines, then the choices in as many columns as they need to fit
  local top, bottom = 7 + #guide + 1, rule_row - 2
  local info = step.info and step.info(w, CW) or {}
  for i, line in ipairs(info) do
    local col = L
    for _, seg in ipairs(line) do
      col = c.put(top + i - 1, col, seg[1], seg[2])
    end
  end
  local itop = top + #info
  local items = step.items(w)
  w.items = items
  local entries = {}
  local group
  for i, it in ipairs(items) do
    if it.group and it.group ~= group then
      if #entries > 0 then
        entries[#entries + 1] = { blank = true }
      end
      entries[#entries + 1] = { header = it.group }
      group = it.group
    end
    entries[#entries + 1] = { item = i }
  end
  local avail = math.max(bottom - itop + 1, 3)
  local cols = math.min(math.max(math.ceil(#entries / avail), 1), 3)
  local per = math.ceil(#entries / cols)
  local colw = math.floor((CW - (cols - 1) * 3) / cols)
  w.places = {}
  for n, e in ipairs(entries) do
    local col_i = math.floor((n - 1) / per)
    local row = itop + (n - 1) % per
    local cx = L + col_i * (colw + 3)
    if e.header then
      c.put(row, cx, e.header, "GuiPickerLabel")
    elseif e.item then
      local it = items[e.item]
      local focused = w.area == "items" and w.focus == e.item
      w.places[e.item] = { row = row, col = cx, colw = colw, column = col_i }
      local hit = { kind = "item", index = e.item }
      local labelw = math.floor(math.min(math.max(colw * 0.42, 18), colw - 6))
      if focused then
        c.fill(row, cx, colw, "GuiWizardFocus")
        c.put(row, cx, "▌", "GuiWizardBar") -- the same bar as the lists' (utils/market.lua)
      end
      -- the whole cell is the choice for the mouse, not only its text
      c.regions[#c.regions + 1] = { row = row, from = cx, to = cx + colw, hit = hit }
      local glyph, ghl
      if it.mark == "radio" or it.mark == "check" then
        glyph, ghl = MARK[it.mark](it.on)
      elseif it.mark == "value" then
        glyph, ghl = it.on and "●" or "○", it.on and "GuiWizardOn" or "GuiWizardOff"
      elseif it.mark == "status" then
        if it.status == "running" then
          glyph, ghl = SPIN[(w.spin or 0) % #SPIN + 1], "GuiWizardKey"
        elseif it.status == "missing" then
          glyph, ghl = "!", "GuiWizardKey"
        elseif it.status == "done" or it.status == "ok" then
          glyph, ghl = "✓", "GuiWizardOn"
        elseif it.status == "failed" then
          glyph, ghl = "✗", "GuiWizardBad"
        else
          glyph, ghl = MARK.check(it.on)
        end
      else
        glyph, ghl = "+", "GuiWizardKey"
      end
      local px = c.put(row, cx + 1, glyph, focused and "GuiWizardFocus" or ghl, hit)
      local lhl = focused and "GuiWizardFocus" or (it.on == false and "GuiPickerDim" or "GuiPickerText")
      px = c.put(row, px + 2, cut(it.label, labelw - 1), lhl, hit)
      local right = cx + colw
      if it.mark == "value" and it.value then
        local v = cut(it.value, 14)
        c.put(
          row,
          cx + 3 + labelw + 1,
          v,
          focused and "GuiWizardFocus" or (it.on and "GuiWizardOn" or "GuiWizardOff"),
          hit
        )
        local room = right - (cx + 3 + labelw + 17) - 1
        if it.desc and room > 4 then
          c.put(row, cx + 3 + labelw + 17, cut(it.desc, room), focused and "GuiWizardFocus" or "GuiPickerDim", hit)
        end
      elseif it.desc then
        local dx = cx + 3 + labelw + 1
        local status = it.mark == "status" and STATUS[it.status] or nil
        local room = right - dx - 1 - (status and 10 or 0)
        if room > 4 then
          c.put(row, dx, cut(it.desc, room), focused and "GuiWizardFocus" or "GuiPickerDim", hit)
        end
        if status and status[1] ~= "" then
          c.put(row, right - 9, status[1], status[2], hit)
        end
      end
    end
  end
  w.per, w.cols = per, cols
  c.flush(w.buf)
  w.regions = c.regions
end

-- ── moving around ──────────────────────────────────────────────────────────

---@param w table
---@param i integer
function M.go(w, i)
  i = math.max(1, math.min(i, #M.STEPS))
  local leaving = w.step
  if leaving and i > leaving then
    M.leave(w, leaving)
    w.done[leaving] = true
  end
  if leaving and M.STEPS[leaving].id == "theme" and w.theme then
    -- previews leave the editor on the last theme under the cursor: put the chosen one back
    pcall(require("appearance").use, w.theme)
  end
  if M.STEPS[i].id == "install" then
    w.plan = nil -- what is missing may have changed with the choices before it
  end
  -- the review's checks, read once per visit (not on every redraw)
  w.checks = M.STEPS[i].id == "review" and require("gui.checks").run() or nil
  w.step = i
  w.area, w.focus, w.bfocus = "items", 1, nil
  -- start on the choice that is already chosen, when there is one
  local items = STEP[M.STEPS[i].id].items(w)
  for n, it in ipairs(items) do
    if it.on and (it.mark == "radio") then
      w.focus = n
    end
  end
  if #items == 0 then
    w.area, w.bfocus = "buttons", nil
  end
  M.draw(w)
end

--- Next, when the step allows it (otherwise the status line already says what is missing).
---@param w table
function M.next(w)
  local ok = STEP[M.STEPS[w.step].id].ready(w)
  if ok and w.step < #M.STEPS then
    M.go(w, w.step + 1)
  end
end

--- What a step does when you leave it forward (the languages are saved where the settings panel saves them).
---@param w table
---@param i integer
function M.leave(w, i)
  if M.STEPS[i].id == "languages" and w.packs then
    local settings = require "core.settings"
    local store = require "prefs.store"
    settings.languages.packs = settings.languages.packs or {}
    for id, on in pairs(w.packs) do
      if w.packs_before[id] ~= on then
        settings.languages.packs[id] = on
        store.save("languages.packs." .. id, on)
      end
    end
  end
end

---@param w table
---@param index integer
function M.choose(w, index)
  local it = (w.items or {})[index]
  if it and it.choose then
    w.focus, w.area = index, "items"
    it.choose(w)
    M.draw(w)
  end
end

---@param w table
---@param index integer
local function focus(w, index)
  local items = w.items or {}
  if #items == 0 then
    return
  end
  index = math.max(1, math.min(index, #items))
  if w.area == "items" and w.focus == index then
    return
  end
  w.area, w.focus = "items", index
  local it = items[index]
  if it.focus then
    if w.preview then
      w.preview:stop()
    end
    w.preview = vim.defer_fn(function()
      if w.area == "items" and w.focus == index then
        it.focus(w)
        M.draw(w)
      end
    end, 110)
  end
  M.draw(w)
end

---@param w table
---@param kind "up"|"down"|"left"|"right"|"tab"
local function move(w, kind)
  local n = #(w.items or {})
  if w.area == "buttons" then
    local bn = #w.buttons
    if kind == "left" then
      w.bfocus = math.max(1, (w.bfocus or 1) - 1)
    elseif kind == "right" then
      w.bfocus = math.min(bn, (w.bfocus or 1) + 1)
    elseif (kind == "up" or kind == "tab") and n > 0 then
      w.area = "items"
    end
    return M.draw(w)
  end
  if kind == "tab" or (kind == "down" and (w.focus or 1) >= n) then
    w.area = "buttons"
    -- the primary button first: Enter there goes on
    for i, b in ipairs(w.buttons or {}) do
      if b.primary then
        w.bfocus = i
      end
    end
    w.bfocus = w.bfocus or #w.buttons
    return M.draw(w)
  end
  local step = ({ up = -1, down = 1, left = -(w.per or n), right = w.per or n })[kind]
  focus(w, (w.focus or 1) + step)
end

---@param w table
local function enter(w)
  if w.area == "buttons" then
    local b = w.buttons[w.bfocus or 1]
    if b and not b.off and b.press then
      return b.press()
    end
    return
  end
  local step = STEP[M.STEPS[w.step].id]
  -- a step with its own primary button (Install, Finish): Enter presses it
  if step.buttons and step.buttons(w) then
    for _, b in ipairs(w.buttons or {}) do
      if b.primary and not b.off and b.press then
        return b.press()
      end
    end
  end
  local ok = step.ready(w)
  local it = (w.items or {})[w.focus or 0]
  -- Enter chooses the one under the cursor while the step still needs a choice; once it is done, it goes on
  if not ok and it and it.choose then
    return M.choose(w, w.focus)
  end
  M.next(w)
end

-- ── installing ─────────────────────────────────────────────────────────────

--- Runs what is checked: the system part in a floating terminal above the page (sudo asks there; it closes by
--- itself when all went well), then Leader's pieces, whose status comes from the checks.
---@param w table
function M.install(w)
  if w.running then
    return
  end
  local pl = plan(w)
  local cmd = M.system_command(w)
  w.running = true
  w.spin = 0
  local spinner = vim.uv.new_timer()
  spinner:start(
    120,
    120,
    vim.schedule_wrap(function()
      if not w.running or not (w.win and vim.api.nvim_win_is_valid(w.win)) then
        return spinner:stop()
      end
      w.spin = w.spin + 1
      M.draw(w)
    end)
  )
  local function leader_part()
    for _, it in ipairs(pl.items) do
      if it.on and it.kind == "leader" and it.status ~= "done" then
        it.status = "running"
        if not pcall(vim.cmd, it.fix) then
          it.status = "failed"
        end
      end
    end
    local tries = 0
    local timer = vim.uv.new_timer()
    timer:start(
      1500,
      1500,
      vim.schedule_wrap(function()
        tries = tries + 1
        local by_id = {}
        for _, c in ipairs(require("gui.checks").run()) do
          by_id[c.id] = c
        end
        local waiting = false
        for _, it in ipairs(pl.items) do
          if it.kind == "leader" and it.status == "running" then
            if by_id[it.check] and by_id[it.check].ok then
              it.status = "done"
            elseif tries > 400 then
              it.status = "failed"
            else
              waiting = true
            end
          end
        end
        if not waiting then
          timer:stop()
          w.running = false
          require("gui").recheck()
        end
        M.draw(w)
      end)
    )
  end
  if not cmd then
    return leader_part()
  end
  for _, it in ipairs(pl.items) do
    if it.on and it.status ~= "done" and (it.kind == "sys" or it.kind == "agent") then
      it.status = "running"
    end
  end
  local W, H = vim.o.columns, vim.o.lines
  local tw, th = math.min(W - 10, 100), math.min(16, H - 8)
  local buf = vim.api.nvim_create_buf(false, true)
  local twin = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((H - th) / 2),
    col = math.floor((W - tw) / 2),
    width = tw,
    height = th,
    style = "minimal",
    border = require("ui.flat").border(),
    title = { { " INSTALLING ", "FlatModalTitle" } },
    title_pos = "left",
    zindex = 250,
  })
  vim.fn.jobstart({ "sh", "-c", "printf '\\033[1m$ %s\\033[0m\\n\\n' \"$0\"; " .. cmd, cmd }, {
    term = true,
    on_exit = vim.schedule_wrap(function(_, code)
      for _, it in ipairs(pl.items) do
        if it.status == "running" and (it.kind == "sys" or it.kind == "agent") then
          local present
          if it.kind == "sys" then
            present = sysdeps.present(it.tool, exe)
          else
            present = exe(it.backend)
          end
          it.status = (code == 0 or present) and "done" or "failed"
        end
      end
      w.agents = nil -- an agent may have arrived
      local function back()
        if vim.api.nvim_win_is_valid(twin) then
          vim.api.nvim_win_close(twin, true)
        end
        if w.win and vim.api.nvim_win_is_valid(w.win) then
          vim.api.nvim_set_current_win(w.win)
        end
      end
      if code == 0 then
        vim.defer_fn(back, 900)
      else
        -- a terminal's buffer cannot be written to: the title says it, the output stays readable
        vim.keymap.set({ "n", "t" }, "q", back, { buffer = buf, nowait = true, desc = "Close" })
        if vim.api.nvim_win_is_valid(twin) then
          vim.api.nvim_win_set_config(twin, {
            title = { { " DID NOT FINISH · read above, q goes back ", "FlatModalTitle" } },
            title_pos = "left",
          })
        end
      end
      leader_part()
    end),
  })
  vim.cmd "startinsert"
end

-- ── opening and closing ────────────────────────────────────────────────────

--- Closes the page, puts the statusline, the tabline and the cursor back, and remembers it was seen.
---@param w table
function M.close(w)
  if w.closed then
    return
  end
  w.closed = true
  if w.refresher then
    w.refresher:stop()
    w.refresher:close()
    w.refresher = nil
  end
  if w.theme then
    pcall(require("appearance").use, w.theme)
  elseif w.theme_before and require("appearance").current() ~= w.theme_before then
    pcall(require("appearance").use, w.theme_before)
  end
  vim.o.laststatus, vim.o.showtabline = w.saved.laststatus, w.saved.showtabline
  require("utils.cursor").show(w)
  if w.win and vim.api.nvim_win_is_valid(w.win) then
    vim.api.nvim_win_close(w.win, true)
  end
  pcall(vim.api.nvim_del_augroup_by_id, w.group)
  require("gui").recheck()
end

---@param w table
function M.finish(w)
  state.update { welcomed = vim.g.leader_gui_version or true, setup = { finished = os.time() } }
  M.close(w)
  -- the first launch asked nothing about projects while the setup was open: now, unless one is open already
  local startup = require "gui.startup"
  if startup.on_start() == "ask" and not startup.is_project(vim.uv.cwd() or "") then
    vim.schedule(startup.ask)
  end
end

---@param opts? { step: string? } start on that step ("review" when the setup was done before)
---@return table w
function M.open(opts)
  opts = opts or {}
  -- one at a time: an open one closes first (so what it hid comes back before this one saves it)
  if M.current and not M.current.closed then
    M.close(M.current)
  end
  local w = {
    done = {},
    saved = { laststatus = vim.o.laststatus, showtabline = vim.o.showtabline },
    theme_before = require("appearance").current(),
  }
  w.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[w.buf].bufhidden = "wipe"
  vim.bo[w.buf].filetype = "leadersetup"
  -- the whole screen: the statusline and the tabline step aside while it is open
  vim.o.laststatus, vim.o.showtabline = 0, 0
  w.win = vim.api.nvim_open_win(w.buf, true, {
    relative = "editor",
    row = 0,
    col = 0,
    width = vim.o.columns,
    height = vim.o.lines - vim.o.cmdheight,
    style = "minimal",
    border = "none",
    zindex = 100,
  })
  vim.wo[w.win].winhighlight = "Normal:Normal,EndOfBuffer:Normal"
  vim.wo[w.win].wrap = false
  -- an install that started elsewhere (the bar's chip) still moves on this page: redraw while one runs
  w.refresher = vim.uv.new_timer()
  w.refresher:start(
    500,
    500,
    vim.schedule_wrap(function()
      local tracker = require("gui.progress").current
      if not w.closed and tracker and tracker.active and M.STEPS[w.step] and M.STEPS[w.step].id == "install" then
        w.spin = (w.spin or 0) + 1
        M.draw(w)
      end
    end)
  )
  require("utils.cursor").hide(w) -- no cursor block on the page (the start screen's hidden cursor)
  pcall(function()
    require("ui.flat.motion").enter { w.win }
  end)

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = w.buf, nowait = true, desc = desc })
  end
  for lhs, kind in pairs {
    ["<Up>"] = "up",
    k = "up",
    ["<Down>"] = "down",
    j = "down",
    ["<Left>"] = "left",
    h = "left",
    ["<Right>"] = "right",
    l = "right",
    ["<Tab>"] = "tab",
  } do
    map(lhs, function()
      move(w, kind)
    end, "Setup move")
  end
  map("<S-Tab>", function()
    move(w, w.area == "buttons" and "up" or "tab")
  end, "Setup move")
  map("<Space>", function()
    if w.area == "items" then
      M.choose(w, w.focus)
    else
      enter(w)
    end
  end, "Setup choose")
  map("<CR>", function()
    enter(w)
  end, "Setup next")
  map("<BS>", function()
    if w.step > 1 then
      M.go(w, w.step - 1)
    end
  end, "Setup back")
  local function leave()
    -- everything was saved as it was chosen: leaving is free, except while an install runs
    if not w.running then
      return M.close(w)
    end
    require("utils.modal").confirm(
      { "An install is running.", "Leave the setup anyway? It keeps running; Ctrl+Shift+W brings the page back." },
      { title = "Setup", confirm = "Leave" },
      function()
        M.close(w)
      end
    )
  end
  map("q", leave, "Setup leave")
  -- Esc closes like everywhere else; Backspace is the way back a step
  map("<Esc>", leave, "Setup leave")

  -- the mouse: the choice under the pointer is the one with the focus, a click does what Space/Enter would
  local function region(pos)
    if pos.winid ~= w.win then
      return nil
    end
    for _, r in ipairs(w.regions or {}) do
      if r.row == pos.line and pos.column - 1 >= r.from and pos.column - 1 < r.to then
        return r.hit
      end
    end
  end
  mouse.on(w.buf, {
    move = function(pos)
      local hit = region(pos)
      if hit and hit.kind == "item" then
        focus(w, hit.index)
      elseif hit and hit.kind == "button" and not (w.area == "buttons" and w.bfocus == hit.index) then
        w.area, w.bfocus = "buttons", hit.index
        M.draw(w)
      end
    end,
    click = function(pos)
      local hit = region(pos)
      if not hit then
        return
      end
      if hit.kind == "item" then
        M.choose(w, hit.index)
      elseif hit.kind == "button" then
        local b = w.buttons[hit.index]
        if b and not b.off and b.press then
          b.press()
        end
      elseif hit.kind == "step" then
        M.go(w, hit.step)
      end
    end,
  })

  w.group = vim.api.nvim_create_augroup("LeaderSetup", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = w.group,
    callback = function()
      if vim.api.nvim_win_is_valid(w.win) then
        vim.api.nvim_win_set_config(
          w.win,
          { relative = "editor", row = 0, col = 0, width = vim.o.columns, height = vim.o.lines - vim.o.cmdheight }
        )
        M.draw(w)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = w.group,
    pattern = tostring(w.win),
    once = true,
    callback = function()
      vim.schedule(function()
        M.close(w)
      end)
    end,
  })
  -- a theme change repaints the page in the new colors
  vim.api.nvim_create_autocmd({ "ColorScheme", "User" }, {
    group = w.group,
    callback = function(ev)
      if ev.event == "ColorScheme" or ev.match == "NvThemeReload" then
        vim.schedule(function()
          M.draw(w)
        end)
      end
    end,
  })

  local start = 1
  for i, s in ipairs(M.STEPS) do
    if s.id == opts.step then
      start = i
      for j = 1, i - 1 do
        w.done[j] = true
      end
      w.reached = i
    end
  end
  if opts.step == "review" then
    -- the setup was done before: everything already counts as chosen
    w.theme = require("appearance").current()
    w.agent = "kept"
    w.install_skipped = true
  end
  M.current = w
  M.go(w, start)
  state.update { welcomed = vim.g.leader_gui_version or true }
  return w
end

return M
