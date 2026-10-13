-- ── Cheatsheet generator (CHEATSHEET.md) ──────────────────────────────────────
-- Reads the REAL keymaps (nvim_get_keymap + the leader menus + the LSP ones) and
-- writes a single markdown file. Nothing is maintained by hand: it is run by
-- scripts/gen-cheatsheet.sh (and the pre-commit hook).
--
-- `desc` convention: the first word is the section ("Harpoon add file");
-- NvCheatsheet (the dashboard's Mappings button) groups the same way and discards
-- single-word descs. Those cases are reported here in `M.warnings`.
local M = {}

---@type string[] keymaps without a useful desc (they don't appear in the cheatsheet)
M.warnings = {}

local MODES = { "n", "x", "o", "i", "t" }

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
  local res = vim.system({ vim.v.progpath, "--clean", "--headless", "-c", "lua " .. script:gsub("\n", " ") }):wait(10000)
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
            entry = { lhs = lhs, modes = {}, text = cap(desc:match "%s(.+)") }
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
  table.insert(lines, "Each menu has its own letter under `<leader>` and only exists where it applies: when pressing `<leader>`")
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

--- nvim-tree buffer keys (defaults + those from plugins/navigation/nvim-tree.lua),
--- read by actually opening the tree.
---@param lines string[]
local function render_tree(lines)
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then
    return table.insert(M.warnings, "nvim-tree not available: section skipped")
  end
  api.tree.open { focus = true }
  local maps = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "NvimTree" then
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if m.desc and m.desc:find "^nvim%-tree: " then
          table.insert(maps, { pretty_lhs(m.lhs), (m.desc:gsub("^nvim%-tree: ", "")) })
        end
      end
    end
  end
  pcall(api.tree.close)
  if #maps == 0 then
    return table.insert(M.warnings, "nvim-tree has no keymaps: section skipped")
  end
  table.sort(maps, function(a, b)
    return a[1] < b[1]
  end)
  table.insert(lines, "## nvim-tree (inside the tree)")
  table.insert(lines, "")
  table.insert(lines, "`Ctrl+n` opens/closes it and `<leader>e` focuses it (see Global shortcuts). `g?` inside the tree lists these same keys.")
  table.insert(lines, "")
  table.insert(lines, "| Key | Action |")
  table.insert(lines, "|---|---|")
  for _, m in ipairs(maps) do
    table.insert(lines, ("| `%s` | %s |"):format(m[1], cell(m[2])))
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
---@param lines string[]
local function render_blink(lines)
  local ok, err = pcall(function()
    local plugin = require("lazy.core.config").plugins["blink.cmp"]
    local opts = require("lazy.core.plugin").values(plugin, "opts", false)
    local user = vim.deepcopy(opts.keymap or {})
    local keymap = vim.deepcopy(require("blink.cmp.keymap.presets").get(user.preset or "default"))
    user.preset = nil
    for lhs, cmds in pairs(user) do
      keymap[lhs] = cmds
    end

    local rows = {}
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
          table.insert(rows, { pretty_lhs(lhs), table.concat(parts, " → ") })
        end
      end
    end
    table.sort(rows, function(a, b)
      return a[1] < b[1]
    end)

    table.insert(lines, "## Autocompletion (blink.cmp, insert mode)")
    table.insert(lines, "")
    table.insert(lines, "Preset `" .. (opts.keymap.preset or "default") .. "` plus the overrides from `plugins/editing/blink.lua`. `→` = tried in order until one applies.")
    table.insert(lines, "")
    table.insert(lines, "| Key | Action |")
    table.insert(lines, "|---|---|")
    for _, r in ipairs(rows) do
      table.insert(lines, ("| `%s` | %s |"):format(r[1], cell(r[2])))
    end
    table.insert(lines, "")
  end)
  if not ok then
    table.insert(M.warnings, "blink.cmp: section skipped (" .. tostring(err) .. ")")
  end
end

---@return string
function M.render()
  local sections = collect_global()
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
  table.insert(lines, "Sections = first word of the `desc` (same as the dashboard's **Mappings** button).")
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
  for _, r in ipairs {
    { "grn", "rename symbol" },
    { "gra", "code action" },
    { "gri", "go to implementation" },
    { "grt", "go to type definition" },
    { "gO", "document symbols" },
    { "K", "hover (documentation)" },
    { "gx", "open the URL or path under the cursor" },
    { "gc / gcc", "comment (operator / line)" },
  } do
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
