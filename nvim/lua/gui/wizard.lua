-- ── Desktop app: the guided setup ────────────────────────────────────────────
-- What the first launch opens (and Ctrl+Shift+W, the bar's "to finish" chip or
-- Help › Welcome later): utils/market.lua with the steps on the left (✓ done,
-- ● here, ○ ahead) and the step on the right, every choice a row you check with
-- Space, Enter or a click:
--   1 Welcome    what this machine is (distro, package manager, GPU, Neovim)
--   2 Theme      a short list, previewed as you move over it
--   3 Languages  the language packs, the ones this machine uses already checked
--   4 Features   the settings worth deciding once (format on save, motion, …)
--   5 Agent      the AI agents found here and their models, or one to install
--   6 Install    what is missing, with the exact command for this Linux family
--                (pacman, apt, dnf, zypper, apk); nothing runs until you say so,
--                sudo asks in a terminal below; status per item, animated
--   7 Review     every choice and the install checks, then Finish (or Restart
--                when new languages need it)
-- Choices apply as they are made and are saved where the settings panel saves
-- them (prefs/store.lua), so they can be changed later in <leader>Sp.
local market = require "utils.market"
local state = require "gui.state"
local sysdeps = require "gui.sysdeps"

local M = {}

M.STEPS = {
  { id = "welcome", title = "Welcome" },
  { id = "theme", title = "Theme" },
  { id = "languages", title = "Languages" },
  { id = "features", title = "Features" },
  { id = "agent", title = "AI agent" },
  { id = "install", title = "Install" },
  { id = "review", title = "Review" },
}

--- The settings worth deciding on day one (prefs ids), with what each one does in a line.
M.FEATURES = {
  { id = "format_on_save.enabled", desc = "formats a file when you save it" },
  { id = "ui.motion", desc = "floats and menus fade in" },
  { id = "ui.blink_cursor", desc = "a blinking cursor: a block in normal mode, a bar in insert" },
  { id = "ui.keys", desc = "shows the keys you press (handy for demos)" },
  { id = "history.word_undo", desc = "u undoes one word at a time while you type" },
  { id = "clipboard.keep", desc = "x and c delete without replacing what you copied" },
  { id = "session.autosave_ms", desc = "how often your windows and files are saved" },
  { id = "agent.verify.enabled", desc = "checks the code after you accept an agent's change" },
  { id = "agent.budget.enabled", desc = "asks before an expensive agent request" },
  { id = "light.force", desc = "light mode: no resident language servers (old machines)" },
}

--- How to install each agent that can be installed from here (the Install step offers it).
M.AGENT_INSTALL = {
  claude = { label = "Claude Code", cmd = "npm install -g @anthropic-ai/claude-code", needs = "npm" },
  opencode = { label = "OpenCode", cmd = "npm install -g opencode-ai", needs = "npm" },
  ollama = { label = "Ollama (local models)", cmd = "curl -fsSL https://ollama.com/install.sh | sh", needs = "curl" },
}

local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function exe(bin)
  return vim.fn.executable(bin) == 1
end

---@param m table
---@return table<string, boolean> pack id → on, as the editor runs now (or as chosen in this setup)
local function packs_now(m)
  if m.packs then
    return m.packs
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
  m.packs, m.packs_before = out, vim.deepcopy(out)
  return out
end

--- What this machine is: read once.
---@param m table
local function system(m)
  if m.sys then
    return m.sys
  end
  local f = io.open "/etc/os-release"
  local release = f and f:read "*a" or nil
  if f then
    f:close()
  end
  m.sys = {
    distro = sysdeps.distro(release) or vim.uv.os_uname().sysname,
    manager = sysdeps.manager(exe),
    root = vim.uv.getuid and vim.uv.getuid() == 0 or false,
    wsl = vim.fn.has "wsl" == 1,
  }
  return m.sys
end

-- ── lines ──────────────────────────────────────────────────────────────────

---@class WizardPane
---@field lines MarketLine[]
---@field rows table<integer, table> line → the choice on it

---@return WizardPane
local function pane()
  local p = { lines = {}, rows = {} }
  function p.add(line, item)
    p.lines[#p.lines + 1] = line
    if item then
      p.rows[#p.lines] = item
    end
  end
  function p.text(s, hl)
    p.add { { "  " .. s, hl or "GuiPickerText" } }
  end
  function p.blank()
    p.add { { "" } }
  end
  function p.wrap(s, width, hl)
    for _, l in ipairs(market.wrap(s, width - 6)) do
      p.text(l, hl or "GuiPickerDim")
    end
  end
  return p
end

---@param p WizardPane
local function header(p, i, title, intro, width)
  p.add { { ("  STEP %d OF %d"):format(i, #M.STEPS), "GuiPickerLabel" } }
  p.add { { "  " .. title, "GuiPickerTitle" } }
  p.blank()
  p.wrap(intro, width)
  p.blank()
end

--- The buttons at the bottom of a step, side by side on one row: a click picks the one under the pointer (by
--- column), Space or Enter on the row the first (the primary one).
---@param p WizardPane
---@param list { label: string, item: table, primary: boolean? }[]
local function buttons(p, list)
  p.blank()
  local segs, chips, col = { { "  " } }, {}, 2
  for i, b in ipairs(list) do
    if i > 1 then
      segs[#segs + 1] = { "   " }
      col = col + 3
    end
    local text = " " .. b.label .. " "
    segs[#segs + 1] = { text, b.primary and "GuiWizardButton" or "GuiWizardButtonSoft" }
    chips[#chips + 1] = { from = col, to = col + #text, item = b.item }
    col = col + #text
  end
  p.add(segs, { kind = "buttons", chips = chips })
end

local function check(on)
  return on and { "  ■ ", "GuiWizardOn" } or { "  □ ", "GuiWizardOff" }
end

local function radio(on)
  return on and { "  ● ", "GuiWizardOn" } or { "  ○ ", "GuiWizardOff" }
end

local function pad(s, w)
  return s .. string.rep(" ", math.max(w - vim.fn.strdisplaywidth(s), 1))
end

local STEP = {}

function STEP.welcome(m, p, width)
  local sys = system(m)
  header(
    p,
    1,
    "Welcome to Leader",
    "A few short steps to make the editor yours: how it looks, your languages, a few features, an AI agent, and what to install (nothing runs without asking). Everything can be changed later in the settings panel (Space S p) or here again (Ctrl+Shift+W).",
    width
  )
  local v = vim.version()
  local facts = {
    { "System", sys.distro .. (sys.wsl and "  ·  WSL" or "") },
    {
      "Packages",
      sys.manager and (sys.manager.id .. "  (" .. sys.manager.family .. ")") or "no package manager found",
    },
    { "GPU", (vim.g.leader_gui_gpu or "starting…"):gsub(",.*$", "") },
    { "Neovim", ("%d.%d.%d"):format(v.major, v.minor, v.patch) },
    { "App", vim.g.leader_gui_version or "?" },
  }
  for _, f in ipairs(facts) do
    p.add { { "  " .. pad(f[1], 12), "GuiPickerLabel" }, { f[2], "GuiPickerText" } }
  end
  buttons(p, { { label = "Start  →", item = { kind = "next" }, primary = true } })
end

function STEP.theme(m, p, width)
  header(
    p,
    2,
    "Pick a look",
    "Move over a theme to see it on the whole editor; Enter keeps it. The terminal theme follows your terminal's colors.",
    width
  )
  local appearance = require "appearance"
  local current = appearance.current()
  local themes = require("gui").THEMES
  for _, group in ipairs { { "DARK", themes.dark }, { "LIGHT", themes.light } } do
    p.text(group[1], "GuiPickerLabel")
    for _, name in ipairs(group[2]) do
      if #vim.api.nvim_get_runtime_file("lua/base46/themes/" .. name .. ".lua", false) > 0 then
        p.add(
          { radio(name == current), { name, name == current and "GuiPickerTitle" or "GuiPickerText" } },
          { kind = "theme", name = name }
        )
      end
    end
    p.blank()
  end
  p.add(
    { radio(current == appearance.TERMINAL), { "terminal (your terminal's palette)", "GuiPickerText" } },
    { kind = "theme", name = appearance.TERMINAL }
  )
  buttons(p, {
    { label = "Next  →", item = { kind = "next" }, primary = true },
    { label = "← Back", item = { kind = "back" } },
  })
end

function STEP.languages(m, p, width)
  header(
    p,
    3,
    "Your languages",
    "Only the checked ones download their language servers, formatters and linters. Checked to start: what this machine already uses. Lua, Markdown, JSON, YAML and TOML are always on.",
    width
  )
  local packs = packs_now(m)
  for _, pk in ipairs(require("languages.packs").packs) do
    local found = vim.tbl_filter(exe, pk.detect)
    local label = { check(packs[pk.id]), { pad(pk.label, 34), packs[pk.id] and "GuiPickerText" or "GuiPickerDim" } }
    if #found > 0 then
      label[#label + 1] = { "found: " .. table.concat(found, ", "), "GuiPickerMark" }
    end
    p.add(label, { kind = "pack", id = pk.id })
  end
  local changed = not vim.deep_equal(packs, m.packs_before)
  if changed then
    p.blank()
    p.text("New languages start after a restart; their tools install in the Install step.", "GuiWizardKey")
  end
  buttons(p, {
    { label = "Next  →", item = { kind = "next" }, primary = true },
    { label = "← Back", item = { kind = "back" } },
  })
end

function STEP.features(m, p, width)
  header(p, 4, "A few features", "On or off now; the settings panel has the rest. Space or a click changes one.", width)
  local prefs = require "prefs"
  for _, f in ipairs(M.FEATURES) do
    local item = prefs.find(f.id)
    if item then
      local value = prefs.text(item)
      local on = value ~= "off" and value ~= "default" and value ~= "only on exit"
      p.add({
        { "  " .. pad(value, 16), on and "GuiWizardOn" or "GuiWizardOff" },
        { pad(item.label, 28), "GuiPickerText" },
        { f.desc, "GuiPickerDim" },
      }, { kind = "feature", id = f.id })
    end
  end
  buttons(p, {
    { label = "Next  →", item = { kind = "next" }, primary = true },
    { label = "← Back", item = { kind = "back" } },
  })
end

--- The agents found here and their models (asked once per opening; CLIs answer at once, local servers quickly).
---@param m table
local function agents(m)
  if m.agents then
    return m.agents
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
  m.agents = out
  return out
end

function STEP.agent(m, p, width)
  header(
    p,
    5,
    "An AI agent",
    "The inline agent (Space a) explains, fixes, reviews and writes code with the agent you pick. It runs through a CLI you already use (Claude Code, OpenCode) or local models (Ollama). Optional: skip it and add one later.",
    width
  )
  local selection = require "agent.selection"
  local cur = selection.current()
  m.agent_install = m.agent_install or {}
  for _, a in ipairs(agents(m)) do
    if a.available then
      p.add { { "  " .. pad(a.name, 12), "GuiPickerTitle" }, { "installed", "GuiPickerMark" } }
      for _, model in ipairs(a.models) do
        local on = cur ~= nil and cur.backend == a.name and cur.model == model
        p.add(
          { { "  " }, radio(on), { model, on and "GuiPickerTitle" or "GuiPickerText" } },
          { kind = "agent", backend = a.name, model = model }
        )
      end
      if #a.models == 0 then
        p.text("    no models listed (Space a m)", "GuiPickerDim")
      end
    elseif M.AGENT_INSTALL[a.name] then
      local want = m.agent_install[a.name] == true
      p.add({
        check(want),
        { pad(a.name, 12), "GuiPickerDim" },
        { "install " .. M.AGENT_INSTALL[a.name].label .. " in the next step", "GuiPickerDim" },
      }, {
        kind = "agent_install",
        backend = a.name,
      })
    end
  end
  p.blank()
  p.add({
    { "  + ", "GuiWizardKey" },
    { "Find local models and servers (Ollama, LM Studio, llama.cpp)…", "GuiPickerText" },
  }, { kind = "agent_setup" })
  buttons(p, {
    { label = "Next  →", item = { kind = "next" }, primary = true },
    { label = "← Back", item = { kind = "back" } },
  })
end

--- What the Install step offers: missing system tools, Leader's own pieces, the agents you asked for.
---@param m table
local function plan(m)
  if m.plan then
    return m.plan
  end
  local sys = system(m)
  local packs = packs_now(m)
  local tools = sysdeps.missing(exe, packs)
  local items = {}
  for _, t in ipairs(tools) do
    items[#items + 1] = { kind = "sys", tool = t, label = t.label, desc = t.why, on = true, status = "todo" }
  end
  local checks = require("gui.checks").run()
  for _, c in ipairs(checks) do
    if not c.ok and c.fix then
      items[#items + 1] =
        { kind = "leader", check = c.id, label = c.label, desc = c.detail, fix = c.fix, on = true, status = "todo" }
    end
  end
  for name, want in pairs(m.agent_install or {}) do
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
  m.plan = { items = items, sys = sys }
  return m.plan
end

---@param m table
---@return string? command for the checked system tools and agents, one line for one terminal
local function system_command(m)
  local pl = plan(m)
  local tools, extra = {}, {}
  for _, it in ipairs(pl.items) do
    if it.on and it.kind == "sys" then
      tools[#tools + 1] = it.tool
    elseif it.on and it.kind == "agent" then
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

local STATUS = {
  todo = { "", "GuiPickerDim" },
  running = { "", "GuiWizardKey" },
  done = { "✓ done", "GuiWizardOn" },
  failed = { "✗ failed", "GuiWizardBad" },
}

function STEP.install(m, p, width)
  header(
    p,
    6,
    "What to install",
    "What Leader still needs here. Nothing runs until you press Install; system packages go through your package manager in a terminal below, where sudo asks for your password.",
    width
  )
  local pl = plan(m)
  if #pl.items == 0 then
    p.text("Everything is installed. Nothing to do here.", "GuiWizardOn")
    buttons(p, {
      { label = "Next  →", item = { kind = "next" }, primary = true },
      { label = "← Back", item = { kind = "back" } },
    })
    return
  end
  local groups = {
    { "sys", "SYSTEM PACKAGES  ·  " .. pl.sys.distro .. (pl.sys.manager and ("  ·  " .. pl.sys.manager.id) or "") },
    { "leader", "LEADER" },
    { "agent", "AGENTS" },
  }
  for _, g in ipairs(groups) do
    local any = vim.iter(pl.items):any(function(it)
      return it.kind == g[1]
    end)
    if any then
      p.text(g[2], "GuiPickerLabel")
      for _, it in ipairs(pl.items) do
        if it.kind == g[1] then
          local st = STATUS[it.status]
          local mark = it.status == "running" and SPIN[(m.spin or 0) % #SPIN + 1] .. " installing" or st[1]
          p.add({
            check(it.on),
            { pad(it.label, 18), "GuiPickerText" },
            { pad(it.desc or "", 46), "GuiPickerDim" },
            { mark, st[2] },
          }, {
            kind = "toggle_install",
            item = it,
          })
        end
      end
      if g[1] == "sys" then
        if not pl.sys.manager then
          p.text("    no package manager found: install them with your system's tools", "GuiWizardKey")
        end
      end
      p.blank()
    end
  end
  local cmd = system_command(m)
  if cmd then
    p.text("This runs:", "GuiPickerLabel")
    for _, l in ipairs(market.wrap(cmd, width - 8)) do
      p.text("  $ " .. l, "GuiWizardCode")
    end
    p.blank()
  end
  local n = #vim.tbl_filter(function(it)
    return it.on and it.status ~= "done"
  end, pl.items)
  buttons(p, {
    {
      label = m.running and (SPIN[(m.spin or 0) % #SPIN + 1] .. " Installing…") or ("Install  (" .. n .. ")"),
      item = { kind = "run" },
      primary = true,
    },
    { label = "Next  →", item = { kind = "next" } },
    { label = "← Back", item = { kind = "back" } },
  })
end

function STEP.review(m, p, width)
  header(
    p,
    7,
    "All set",
    "What you chose and what this machine has now. Finish closes this; everything stays changeable in Space S p.",
    width
  )
  local appearance = require "appearance"
  local selection = require "agent.selection"
  local cur = selection.current()
  local on = {}
  for _, pk in ipairs(require("languages.packs").packs) do
    if packs_now(m)[pk.id] then
      on[#on + 1] = pk.label:gsub(":.*$", "")
    end
  end
  for _, f in ipairs {
    { "Theme", appearance.current() },
    { "Languages", #on > 0 and table.concat(on, ", ") or "the base only" },
    { "Agent", cur and selection.label(cur) or "none" },
  } do
    local value = f[2]
    if vim.fn.strdisplaywidth(value) > width - 20 then
      value = vim.fn.strcharpart(value, 0, width - 21) .. "…"
    end
    p.add { { "  " .. pad(f[1], 12), "GuiPickerLabel" }, { value, "GuiPickerText" } }
  end
  p.blank()
  p.text("THIS MACHINE", "GuiPickerLabel")
  for _, c in ipairs(require("gui.checks").run()) do
    p.add({
      { c.ok and "  ✓ " or "  ✗ ", c.ok and "GuiWizardOn" or "GuiWizardBad" },
      { pad(c.label, 18), "GuiPickerText" },
      { c.detail, "GuiPickerDim" },
    }, c.ok and nil or {
      kind = "goto",
      step = 6,
    })
  end
  local restart = m.packs_before and not vim.deep_equal(packs_now(m), m.packs_before)
  local row = { { label = "Finish", item = { kind = "finish" }, primary = true } }
  if restart then
    row[#row + 1] = { label = "Restart Leader (new languages)", item = { kind = "restart" } }
  end
  row[#row + 1] = { label = "Open a project…", item = { kind = "projects" } }
  buttons(p, row)
end

-- ── the market ─────────────────────────────────────────────────────────────

---@param m table
function M.rows(m)
  local rows = { { title = "SET UP LEADER" }, { spacer = true } }
  for i in ipairs(M.STEPS) do
    rows[#rows + 1] = { step = i }
  end
  return rows
end

function M.selectable(row)
  return row.step ~= nil
end

---@param m table
local function list_line(m)
  return function(row)
    if row.title then
      return { { "  " .. row.title, "NvModalKey" } }
    elseif row.spacer then
      return { { "" } }
    end
    local i = row.step
    local here = i == m.step
    local done = (m.done or {})[i]
    local icon = here and { "  ● ", "NvModalKey" }
      or done and { "  ✓ ", "NvModalMark" }
      or { "  ○ ", "NvModalMuted" }
    return {
      icon,
      { ("%d  %s"):format(i, M.STEPS[i].title), here and "NvModalKey" or done and "NvModalFile" or "NvModalMuted" },
    }
  end
end

---@param m table
---@param row table?
---@param width integer
---@return MarketLine[], table<integer, table>
function M.pane(m, row, width)
  if not row or not row.step then
    return {}, {}
  end
  m.step = row.step
  local p = pane()
  STEP[M.STEPS[row.step].id](m, p, width)
  return p.lines, p.rows
end

--- Goes to a step: the list's cursor, the pane, the keyboard there, on its first choice.
---@param m table
---@param i integer
function M.go(m, i)
  i = math.max(1, math.min(i, #M.STEPS))
  if m.step and m.step < i then
    M.leave(m, m.step)
  end
  m.done = m.done or {}
  if m.step and i > m.step then
    m.done[m.step] = true
  end
  for line, r in ipairs(m.rows) do
    if r.step == i then
      pcall(vim.api.nvim_win_set_cursor, m.wins.list, { line, 0 })
    end
  end
  if M.STEPS[i].id == "install" then
    m.plan = nil -- what is missing may have changed with the choices before it
  end
  market.refresh(m)
  market.focus(m, "pane")
  local first
  for line in pairs(m.pane_rows or {}) do
    first = math.min(first or line, line)
  end
  if first then
    pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { first, 0 })
  end
end

--- What a step does when you leave it forward (the languages are saved where the settings panel saves them).
---@param m table
---@param i integer
function M.leave(m, i)
  if M.STEPS[i].id == "languages" and m.packs then
    local settings = require "core.settings"
    local store = require "prefs.store"
    settings.languages.packs = settings.languages.packs or {}
    for id, on in pairs(m.packs) do
      if m.packs_before[id] ~= on then
        settings.languages.packs[id] = on
        store.save("languages.packs." .. id, on)
      end
    end
  end
end

--- Runs what is checked in the Install step: the system part in a terminal (sudo asks there), then Leader's pieces.
---@param m table
function M.install(m)
  if m.running then
    return
  end
  local pl = plan(m)
  local cmd = system_command(m)
  local function leader_part()
    for _, it in ipairs(pl.items) do
      if it.on and it.kind == "leader" and it.status ~= "done" then
        it.status = "running"
        local ok = pcall(vim.cmd, it.fix)
        if not ok then
          it.status = "failed"
        end
      end
    end
    -- their state comes from the checks: re-read until they pass (Mason and parsers work in the background)
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
        local pending = false
        for _, it in ipairs(pl.items) do
          if it.kind == "leader" and it.status == "running" then
            if by_id[it.check] and by_id[it.check].ok then
              it.status = "done"
            elseif tries > 400 then
              it.status = "failed"
            else
              pending = true
            end
          end
        end
        if not pending then
          timer:stop()
          m.running = false
          require("gui").recheck()
        end
        if m.wins and vim.api.nvim_win_is_valid(m.wins.list) then
          market.refresh(m)
        end
      end)
    )
  end
  m.running = true
  -- the spinner: a frame every 120 ms while something runs
  m.spin = 0
  local spinner = vim.uv.new_timer()
  spinner:start(
    120,
    120,
    vim.schedule_wrap(function()
      if not m.running or not (m.wins and vim.api.nvim_win_is_valid(m.wins.list)) then
        return spinner:stop()
      end
      m.spin = m.spin + 1
      market.refresh(m)
    end)
  )
  if not cmd then
    return leader_part()
  end
  for _, it in ipairs(pl.items) do
    if it.on and (it.kind == "sys" or it.kind == "agent") then
      it.status = "running"
    end
  end
  -- a terminal under the wizard: the command is printed first, sudo asks for the password right there
  vim.cmd "botright 14new"
  local term = vim.api.nvim_get_current_buf()
  vim.bo[term].bufhidden = "wipe"
  vim.fn.jobstart({ "sh", "-c", "printf '\\033[1m$ %s\\033[0m\\n\\n' \"$0\"; " .. cmd, cmd }, {
    term = true,
    on_exit = vim.schedule_wrap(function(_, code)
      for _, it in ipairs(pl.items) do
        if it.status == "running" and (it.kind == "sys" or it.kind == "agent") then
          local present = it.kind == "sys" and sysdeps.present(it.tool, exe) or exe(it.backend)
          it.status = (code == 0 or present) and "done" or "failed"
        end
      end
      m.agents = nil -- an agent may have arrived
      leader_part()
    end),
  })
  vim.cmd "startinsert"
end

---@param m table
---@param item table
---@param column integer? 1-based screen column of a click (a row of buttons picks the one under it)
function M.choose(m, item, column)
  if not item then
    return
  end
  if item.kind == "buttons" then
    local pick = item.chips[1]
    for _, c in ipairs(item.chips) do
      if column and column - 1 >= c.from and column - 1 < c.to then
        pick = c
      end
    end
    return M.choose(m, pick.item)
  end
  local kind = item.kind
  if kind == "next" then
    return M.go(m, (m.step or 1) + 1)
  elseif kind == "back" then
    return M.go(m, (m.step or 1) - 1)
  elseif kind == "goto" then
    return M.go(m, item.step)
  elseif kind == "theme" then
    pcall(require("appearance").use, item.name)
  elseif kind == "pack" then
    local packs = packs_now(m)
    packs[item.id] = not packs[item.id]
  elseif kind == "feature" then
    local prefs = require "prefs"
    local it = prefs.find(item.id)
    if it then
      prefs.cycle(it)
    end
  elseif kind == "agent" then
    require("agent.selection").set(item.backend, item.model)
    require("gui").update()
  elseif kind == "agent_install" then
    m.agent_install[item.backend] = not m.agent_install[item.backend]
  elseif kind == "agent_setup" then
    market.close(m)
    return require("agent.setup").open()
  elseif kind == "toggle_install" then
    if item.item.status ~= "running" then
      item.item.on = not item.item.on
    end
  elseif kind == "run" then
    return M.install(m)
  elseif kind == "finish" then
    state.update { welcomed = vim.g.leader_gui_version or true, setup = { finished = os.time() } }
    market.close(m)
    return require("gui").recheck()
  elseif kind == "restart" then
    state.update { welcomed = vim.g.leader_gui_version or true }
    if vim.g.leader_gui_channel then
      vim.rpcnotify(vim.g.leader_gui_channel, "leader_window", "restart:" .. (vim.uv.cwd() or ""))
    end
    return
  elseif kind == "projects" then
    market.close(m)
    return require("gui.picker").open()
  end
  market.refresh(m)
end

---@param opts? { step: string? } start on that step ("review" when the setup was done before)
function M.open(opts)
  opts = opts or {}
  -- the market's state is this very table (market.new fills it): the closures below can use it from the start
  local m = { done = {} }
  local function at_cursor()
    return m.pane_rows[vim.api.nvim_win_get_cursor(m.wins.pane)[1]]
  end
  local def = {
    title = "Set up Leader",
    rows = M.rows,
    selectable = M.selectable,
    list_line = function(row)
      return list_line(m)(row)
    end,
    pane = M.pane,
    summary = function()
      local done = vim.tbl_count(m.done or {})
      local bar = string.rep("■", done) .. string.rep("□", #M.STEPS - done)
      return { { { "  " .. bar .. ("   %d of %d steps"):format(done, #M.STEPS), "NvModalMuted" } } }
    end,
    hints = function(_, mode)
      if mode == "pane" then
        return { { "Space", "choose" }, { "n", "next" }, { "b", "back" }, { "Esc", "steps" } }
      end
      return { { "⏎", "open the step" }, { "n", "next" }, { "q", "close" } }
    end,
    summary_rows = 3,
    read = function(mk, row)
      if row and row.step then
        M.go(mk, row.step)
      end
    end,
    pane_click = function(mk, item, _, column)
      M.choose(mk, item, column)
    end,
    keys = {
      pane = {
        {
          "<Space>",
          function()
            M.choose(m, at_cursor())
          end,
          "Choose",
        },
        {
          "<CR>",
          function()
            local item = at_cursor()
            M.choose(m, item)
            -- a theme chosen with Enter goes on to the next step
            if item and item.kind == "theme" then
              M.go(m, m.step + 1)
            end
          end,
          "Choose",
        },
        {
          "x",
          function()
            M.choose(m, at_cursor())
          end,
          "Choose",
        },
      },
      all = {
        {
          "n",
          function()
            M.go(m, (m.step or 1) + 1)
          end,
          "Next step",
        },
        {
          "b",
          function()
            M.go(m, (m.step or 1) - 1)
          end,
          "Previous step",
        },
      },
    },
    help = { { "Space ⏎ x", "choose the row under the cursor" }, { "n b", "next / previous step" } },
  }
  market.new(def, m)
  -- the pane is where you choose: its row under the cursor stands out
  vim.wo[m.wins.pane].cursorline = true
  vim.wo[m.wins.pane].cursorlineopt = "line" -- the config's own is "number": the chosen row lights up whole
  -- the theme step previews the theme under the cursor
  local timer = vim.uv.new_timer()
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = m.bufs.pane,
    callback = function()
      local item = m.pane_rows[vim.api.nvim_win_get_cursor(m.wins.pane)[1]]
      timer:stop()
      if item and item.kind == "theme" then
        timer:start(
          120,
          0,
          vim.schedule_wrap(function()
            pcall(require("appearance").use, item.name)
          end)
        )
      end
    end,
  })
  local start = 1
  for i, s in ipairs(M.STEPS) do
    if s.id == opts.step then
      start = i
      for j = 1, i - 1 do
        m.done[j] = true
      end
    end
  end
  m.step = start
  M.go(m, start)
  state.update { welcomed = vim.g.leader_gui_version or true }
  return m
end

return M
