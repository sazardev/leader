-- ── Cheatsheet generator (CHEATSHEET.md) ──────────────────────────────────────
-- Reads the REAL keymaps (nvim_get_keymap + the leader menus + the LSP ones) and
-- writes a single markdown file. Nothing is maintained by hand: it is run by
-- scripts/gen-cheatsheet.sh (and the pre-commit hook).
--
-- `desc` convention: the first word is the section ("Harpoon add file");
-- the Markdown and the live Mappings view (lua/cheatsheet) group by it and discard
-- single-word descs. Those cases are reported here in `M.warnings`.
local M = {}

---@type string[] keymaps without a useful desc (they don't appear in the cheatsheet)
M.warnings = {}

local MODES = { "n", "x", "o", "i", "t" }
M.MODES = MODES

-- Sections that NvChad names oddly (first word of its desc)
local HEADING_ALIAS = { Switch = "Window", Toggle = "Comment", Nvimtree = "Nvim-tree" }

--- Keymaps that Neovim ships with ("mode\0lhs\0desc"), measured with `nvim --clean`:
--- so the native keys of each version don't have to be listed by hand.
---@return table<string, boolean>
local function native_baseline()
  local script = [[
    local out = {}
    for _, mode in ipairs { "n", "x", "o", "i", "t" } do
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        table.insert(out, table.concat({ mode, m.lhs, m.desc or "" }, "\0"))
      end
    end
    io.stdout:write(table.concat(out, "\n"))
    vim.cmd "qa!"
  ]]
  local res =
    vim.system({ vim.v.progpath, "--clean", "--headless", "-c", "lua " .. script:gsub("\n", " ") }):wait(10000)
  local set = {}
  for line in (res.stdout or ""):gmatch "[^\n]+" do
    set[line] = true
  end
  return set
end

---@param lhs string
---@return string
local function pretty_lhs(lhs)
  lhs = lhs:gsub("^ ", "<leader>"):gsub(" ", "<Space>")
  lhs = lhs:gsub("<M%-", "<A-"):gsub("<C%-(%u)>", function(c)
    return "<C-" .. c:lower() .. ">"
  end)
  return lhs
end
M.pretty_lhs = pretty_lhs

---@param s string
---@return string
local function cap(s)
  return (s:gsub("^%l", string.upper))
end

---@param s string
---@return string
local function cell(s)
  return (s:gsub("|", "\\|"))
end

--- Global keymaps grouped by section: { [section] = { {lhs, modes, text}... } }
---@return table<string, table[]>
local function collect_global()
  local sections, index = {}, {}
  local native = native_baseline()
  M.warnings = {}

  for _, mode in ipairs(MODES) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      local desc = m.desc
      local skip = desc == nil
        or m.lhs:find("<Plug>", 1, true)
        or native[table.concat({ mode, m.lhs, desc }, "\0")]
        or desc:find "^vim%."
      if not skip then
        local words = select(2, desc:gsub("%S+", ""))
        if words < 2 or desc:find "\n" then
          table.insert(M.warnings, ("%s (%s): desc `%s` needs 2+ words"):format(pretty_lhs(m.lhs), mode, desc))
        else
          local lhs = pretty_lhs(m.lhs)
          local key = lhs .. "\0" .. desc
          local entry = index[key]
          if not entry then
            local heading = cap(desc:match "%S+")
            heading = HEADING_ALIAS[heading] or heading
            entry = { lhs = lhs, modes = {}, text = cap(desc:match "%s(.+)"), full = desc, section = heading }
            index[key] = entry
            sections[heading] = sections[heading] or {}
            table.insert(sections[heading], entry)
          end
          table.insert(entry.modes, mode)
        end
      end
    end
  end
  return sections
end
M.global = collect_global

---@param lines string[]
---@param entries table[]
local function section_table(lines, entries)
  table.sort(entries, function(a, b)
    return a.lhs < b.lhs
  end)
  table.insert(lines, "| Key | Mode | Action |")
  table.insert(lines, "|---|---|---|")
  for _, e in ipairs(entries) do
    table.insert(lines, ("| `%s` | %s | %s |"):format(e.lhs, table.concat(e.modes, ","), cell(e.text)))
  end
  table.insert(lines, "")
end

---@param ctx table
---@return string
local function where(ctx)
  if ctx.global then
    return "global"
  end
  if ctx.where then
    return ctx.where
  end
  return table.concat(
    vim.tbl_map(function(ft)
      return "`" .. ft .. "`"
    end, ctx.filetypes or {}),
    ", "
  )
end

---@param lines string[]
local function render_menus(lines)
  local contexts = require("menus").contexts()
  table.sort(contexts, function(a, b)
    return a.name < b.name
  end)

  table.insert(lines, "## Leader menus")
  table.insert(lines, "")
  table.insert(
    lines,
    "Each menu has its own letter under `<leader>` and only exists where it applies: when pressing `<leader>`"
  )
  table.insert(lines, "which-key only shows what belongs to the current buffer.")
  table.insert(lines, "")
  table.insert(lines, "| Letter | Menu | Where it exists |")
  table.insert(lines, "|---|---|---|")
  for _, ctx in ipairs(contexts) do
    table.insert(lines, ("| `<leader>%s` | %s | %s |"):format(ctx.prefix, ctx.name, where(ctx)))
  end
  table.insert(lines, "")

  for _, ctx in ipairs(contexts) do
    table.insert(lines, ("### %s — `<leader>%s`"):format(ctx.name, ctx.prefix))
    table.insert(lines, "")
    table.insert(lines, "_Where: " .. where(ctx) .. "_")
    table.insert(lines, "")
    table.insert(lines, "| Key | Action |")
    table.insert(lines, "|---|---|")
    for _, m in ipairs(ctx.maps) do
      table.insert(lines, ("| `<leader>%s%s` | %s |"):format(ctx.prefix, m[1], cell(m[2])))
    end
    table.insert(lines, "")
  end
end

---@param lines string[]
local function render_lsp(lines)
  table.insert(lines, "## LSP (when a server attaches)")
  table.insert(lines, "")
  table.insert(lines, "Buffer-local keymaps from `servers/on_attach.lua`.")
  table.insert(lines, "")
  table.insert(lines, "| Key | Action |")
  table.insert(lines, "|---|---|")
  for _, m in ipairs(require("servers.on_attach").keymaps()) do
    table.insert(lines, ("| `%s` | %s |"):format(pretty_lhs(m[1]), cell((m[3]:gsub("^LSP ", "")))))
  end
  table.insert(lines, "")
end

--- nvim-tree buffer keys (defaults + those from plugins/navigation/nvim-tree.lua).
--- Its API generates them on a scratch buffer, so reading the cheatsheet never opens or closes the user's tree.
---@return table[]?
function M.tree()
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok or not api.config or not api.config.mappings or not api.config.mappings.get_keymap then
    table.insert(M.warnings, "nvim-tree not available: section skipped")
    return nil
  end
  local got, maps = pcall(api.config.mappings.get_keymap)
  if not got then
    table.insert(M.warnings, "nvim-tree: section skipped (" .. tostring(maps) .. ")")
    return nil
  end
  local out = {}
  for _, m in ipairs(maps) do
    if m.desc and m.desc:find "^nvim%-tree: " then
      local modes = {}
      for mode in (m.mode or "n"):gmatch "." do
        table.insert(modes, mode == "v" and "x" or mode)
      end
      table.insert(out, { key = pretty_lhs(m.lhs), action = m.desc:gsub("^nvim%-tree: ", ""), modes = modes })
    end
  end
  if #out == 0 then
    table.insert(M.warnings, "nvim-tree has no keymaps: section skipped")
    return nil
  end
  return out
end

---@param lines string[]
local function render_tree(lines)
  local maps = M.tree()
  if not maps then
    return
  end
  table.sort(maps, function(a, b)
    return a.key < b.key
  end)
  -- The Markdown section has always described Normal mode; the live view also keeps Visual modes.
  local normal, seen = {}, {}
  for _, m in ipairs(maps) do
    local signature = m.key .. "\0" .. m.action
    if vim.tbl_contains(m.modes, "n") and not seen[signature] then
      seen[signature] = true
      table.insert(normal, m)
    end
  end
  table.insert(lines, "## nvim-tree (inside the tree)")
  table.insert(lines, "")
  table.insert(
    lines,
    "`Ctrl+n` opens/closes it and `<leader>e` focuses it (see Global shortcuts). `g?` inside the tree lists these same keys."
  )
  table.insert(lines, "")
  table.insert(lines, "| Key | Action |")
  table.insert(lines, "|---|---|")
  for _, m in ipairs(normal) do
    table.insert(lines, ("| `%s` | %s |"):format(m.key, cell(m.action)))
  end
  table.insert(lines, "")
end

-- blink.cmp command vocabulary (fixed names from the library)
local BLINK_CMDS = {
  select_next = "next item",
  select_prev = "previous item",
  accept = "accept item",
  select_and_accept = "accept item",
  snippet_forward = "next snippet placeholder",
  snippet_backward = "previous snippet placeholder",
  show = "open menu",
  hide = "close menu",
  cancel = "close menu",
  show_documentation = "show documentation",
  hide_documentation = "hide documentation",
  scroll_documentation_up = "scroll documentation up",
  scroll_documentation_down = "scroll documentation down",
  show_signature = "show signature help",
  hide_signature = "hide signature help",
}

--- Autocompletion: preset + overrides from plugins/editing/blink.lua (insert mode)
---@return table[]?, string?
function M.blink()
  local preset
  local ok, rows = pcall(function()
    local plugin = require("lazy.core.config").plugins["blink.cmp"]
    local opts = require("lazy.core.plugin").values(plugin, "opts", false)
    local user = vim.deepcopy(opts.keymap or {})
    local keymap = vim.deepcopy(require("blink.cmp.keymap.presets").get(user.preset or "default"))
    user.preset = nil
    for lhs, cmds in pairs(user) do
      keymap[lhs] = cmds
    end

    local out = {}
    for lhs, cmds in pairs(keymap) do
      if cmds then
        local parts = {}
        for _, c in ipairs(cmds) do
          if type(c) == "function" then
            table.insert(parts, require("utils.blinkkeys").LABELS[c] or "custom action")
          elseif c ~= "fallback" and c ~= "fallback_to_mappings" then
            table.insert(parts, BLINK_CMDS[c] or c)
          end
        end
        if #parts > 0 then
          table.insert(out, { key = pretty_lhs(lhs), action = table.concat(parts, " → ") })
        end
      end
    end
    table.sort(out, function(a, b)
      return a.key < b.key
    end)
    preset = opts.keymap.preset or "default"
    return out
  end)
  if not ok then
    return nil, tostring(rows)
  end
  return rows, preset
end

---@param lines string[]
local function render_blink(lines)
  local rows, preset = M.blink()
  if not rows then
    return table.insert(M.warnings, "blink.cmp: section skipped (" .. tostring(preset) .. ")")
  end
  table.insert(lines, "## Autocompletion (blink.cmp, insert mode)")
  table.insert(lines, "")
  table.insert(
    lines,
    "Preset `"
      .. preset
      .. "` plus the overrides from `plugins/editing/blink.lua`. `→` = tried in order until one applies."
  )
  table.insert(lines, "")
  table.insert(lines, "| Key | Action |")
  table.insert(lines, "|---|---|")
  for _, r in ipairs(rows) do
    table.insert(lines, ("| `%s` | %s |"):format(r.key, cell(r.action)))
  end
  table.insert(lines, "")
end

-- Native Neovim 0.11 shortcuts shown alongside the config's own keys.
M.NATIVE = {
  { "grn", "rename symbol" },
  { "gra", "code action" },
  { "gri", "go to implementation" },
  { "grt", "go to type definition" },
  { "gO", "document symbols" },
  { "K", "hover (documentation)" },
  { "gx", "open the URL or path under the cursor" },
  { "gc / gcc", "comment (operator / line)" },
}

---@param value string|string[]?
---@return string[]
local function mode_list(value)
  if type(value) == "table" then
    return value
  end
  return { value or "n" }
end

--- One flat, searchable collection for the live Mappings view. The Markdown keeps its sections;
--- both read the same real sources, and a leader menu wins over its duplicate global mapping.
---@return table[]
function M.entries()
  M.warnings = {}
  local out, index = {}, {}
  local priority = { native = 0, tree = 1, completion = 1, global = 2, lsp = 3, menu = 4 }
  local function add(entry)
    entry.modes = mode_list(entry.modes)
    local signature = entry.key .. "\0" .. (entry.full or entry.action):lower()
    local old = index[signature]
    if old then
      for _, mode in ipairs(entry.modes) do
        if not vim.tbl_contains(old.modes, mode) then
          table.insert(old.modes, mode)
        end
      end
      if priority[entry.source] > priority[old.source] then
        local modes = old.modes
        for k, v in pairs(entry) do
          old[k] = v
        end
        old.modes, old.priority = modes, priority[entry.source]
      end
      return
    end
    entry.priority = priority[entry.source]
    index[signature] = entry
    table.insert(out, entry)
  end

  local ok, sections = pcall(M.global)
  if ok then
    for _, list in pairs(sections) do
      for _, e in ipairs(list) do
        add {
          key = e.lhs,
          action = e.text,
          full = e.full or (e.section .. " " .. e.text),
          modes = e.modes,
          language = "Global",
          group = e.section,
          source = "global",
          scope = "Global",
          where = "everywhere",
        }
      end
    end
  else
    table.insert(M.warnings, "global mappings: skipped (" .. tostring(sections) .. ")")
  end

  local contexts_ok, contexts = pcall(function()
    return require("menus").contexts()
  end)
  if contexts_ok then
    for _, ctx in ipairs(contexts) do
      local language = ctx.global and "Global" or (ctx.name == "Git" or ctx.name == "GitHub") and "Git" or ctx.name
      local available = ctx.where or (ctx.global and "everywhere" or table.concat(ctx.filetypes or {}, ", "))
      for _, m in ipairs(ctx.maps) do
        add {
          key = pretty_lhs("<leader>" .. ctx.prefix .. m[1]),
          action = m[2],
          full = require("menus").desc(ctx, m[2]),
          modes = m[4] or "n",
          language = language,
          group = ctx.name,
          source = "menu",
          scope = ctx.global and "Global" or "Buffer-local",
          where = available ~= "" and available or "this menu's buffers",
          prefix = "<leader>" .. ctx.prefix,
        }
      end
    end
  else
    table.insert(M.warnings, "leader menus: skipped (" .. tostring(contexts) .. ")")
  end

  local lsp_ok, lsp = pcall(function()
    return require("servers.on_attach").keymaps()
  end)
  if lsp_ok then
    for _, m in ipairs(lsp) do
      add {
        key = pretty_lhs(m[1]),
        action = m[3]:gsub("^LSP ", ""),
        full = m[3],
        modes = "n",
        language = "Global",
        group = "LSP",
        source = "lsp",
        scope = "Buffer-local",
        where = "buffers with an attached language server",
      }
    end
  else
    table.insert(M.warnings, "LSP mappings: skipped (" .. tostring(lsp) .. ")")
  end

  local blink, blink_err = M.blink()
  if blink then
    for _, e in ipairs(blink) do
      add {
        key = e.key,
        action = e.action,
        modes = "i",
        language = "Global",
        group = "Autocompletion",
        source = "completion",
        scope = "Insert mode",
        where = "blink.cmp completion",
      }
    end
  else
    table.insert(M.warnings, "blink.cmp: skipped (" .. tostring(blink_err) .. ")")
  end

  local tree = M.tree()
  for _, e in ipairs(tree or {}) do
    add {
      key = e.key,
      action = e.action,
      modes = e.modes,
      language = "Global",
      group = "File tree",
      source = "tree",
      scope = "Buffer-local",
      where = "inside nvim-tree",
    }
  end

  for _, e in ipairs(M.NATIVE) do
    add {
      key = e[1],
      action = e[2],
      modes = "n",
      language = "Global",
      group = "Neovim",
      source = "native",
      scope = "Native",
      where = "built into Neovim 0.11",
    }
  end

  local examples = require "cheatsheet.examples"
  for _, entry in ipairs(out) do
    local described = examples.describe(entry)
    entry.example = described.example
    entry.usage = described.usage
    entry.steps = described.steps
    entry.result = described.result
    entry.notes = described.notes
    entry.note = described.note
    entry.search = {
      key = entry.key:lower(),
      action = entry.action:lower(),
      full = (entry.full or ""):lower(),
      language = (entry.language or ""):lower(),
      group = (entry.group or ""):lower(),
      source = entry.source:lower(),
      where = (entry.where or ""):lower(),
      docs = entry.example:lower(),
    }
  end

  table.sort(out, function(a, b)
    if a.group ~= b.group then
      return a.group:lower() < b.group:lower()
    end
    if a.key ~= b.key then
      return a.key < b.key
    end
    return a.action:lower() < b.action:lower()
  end)
  return out
end

---@return string
function M.render()
  local sections = M.global()
  local names = vim.tbl_keys(sections)
  table.sort(names)

  local lines = {
    "# Cheatsheet",
    "",
    "<!-- GENERATED by scripts/gen-cheatsheet.sh — DO NOT edit by hand. -->",
    "",
    "> Generated from the config's real keymaps (`nvim_get_keymap`, `menus/`, `servers/on_attach.lua`).",
    "> Regenerated automatically on every commit (`.githooks/pre-commit`). `<leader>` = `Space`.",
    "> This is the ONLY source of keys. What can't be derived from code (what each thing does, workflows, tools): [`docs/cheatsheets/`](docs/cheatsheets/README.md).",
    "",
  }

  render_menus(lines)
  render_lsp(lines)
  render_blink(lines)
  render_tree(lines)

  table.insert(lines, "## Global shortcuts")
  table.insert(lines, "")
  table.insert(lines, "Sections = first word of the `desc` (the live **Mappings** view groups the same way).")
  table.insert(lines, "")
  for _, name in ipairs(names) do
    table.insert(lines, "### " .. name)
    table.insert(lines, "")
    section_table(lines, sections[name])
  end

  table.insert(lines, "## Native Neovim 0.11 (not from this config)")
  table.insert(lines, "")
  table.insert(lines, "| Key | Action |")
  table.insert(lines, "|---|---|")
  for _, r in ipairs(M.NATIVE) do
    table.insert(lines, ("| `%s` | %s |"):format(r[1], r[2]))
  end
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

--- Wait for the startup keymaps to exist (NvChad loads them with vim.schedule) and
--- fire VeryLazy, which doesn't arrive on its own in headless (there's no UIEnter): that way the plugins that
--- map on load (mini.move...) end up the same as in a real session.
---@return boolean
function M.wait_ready()
  local ready = vim.wait(10000, function()
    return vim.fn.maparg(" ff", "n") ~= "" and vim.fn.maparg("s", "n") ~= ""
  end, 50)
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
  vim.wait(200)
  return ready
end

--- Write the cheatsheet; with `check` it only compares and returns false if it differs
---@param path string
---@param check? boolean
---@return boolean
function M.write(path, check)
  local content = M.render() .. "\n"
  if check then
    local ok, current = pcall(vim.fn.readfile, path, "b")
    return ok and table.concat(current, "\n") == content
  end
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), path, "b")
  return true
end

return M
