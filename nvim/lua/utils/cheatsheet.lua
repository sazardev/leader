-- ── Generador del cheatsheet (CHEATSHEET.md) ─────────────────────────────────
-- Lee los keymaps REALES (nvim_get_keymap + los menús del leader + los de LSP) y
-- escribe un único markdown. Nada se mantiene a mano: lo ejecuta
-- scripts/gen-cheatsheet.sh (y el hook pre-commit).
--
-- Convención de `desc`: la primera palabra es la sección ("Harpoon add file");
-- NvCheatsheet (botón Mappings del dashboard) agrupa igual y descarta los desc
-- de una sola palabra. Aquí se avisa de esos casos en `M.warnings`.
local M = {}

---@type string[] keymaps sin desc útil (no salen en el cheatsheet)
M.warnings = {}

local MODES = { "n", "x", "o", "i", "t" }

-- Secciones que NvChad nombra raro (primera palabra de su desc)
local HEADING_ALIAS = { Switch = "Window", Toggle = "Comment", Nvimtree = "Nvim-tree" }

--- Keymaps que Neovim trae de fábrica ("mode\0lhs\0desc"), medidos con `nvim --clean`:
--- así no hay que listar a mano las teclas nativas de cada versión.
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

--- Keymaps globales agrupados por sección: { [seccion] = { {lhs, modes, text}... } }
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
  table.insert(lines, "| Tecla | Modo | Acción |")
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

  table.insert(lines, "## Menús del leader")
  table.insert(lines, "")
  table.insert(lines, "Cada menú tiene su letra bajo `<leader>` y solo existe donde aplica: al pulsar `<leader>`")
  table.insert(lines, "which-key muestra únicamente lo del buffer actual.")
  table.insert(lines, "")
  table.insert(lines, "| Letra | Menú | Dónde existe |")
  table.insert(lines, "|---|---|---|")
  for _, ctx in ipairs(contexts) do
    table.insert(lines, ("| `<leader>%s` | %s | %s |"):format(ctx.prefix, ctx.name, where(ctx)))
  end
  table.insert(lines, "")

  for _, ctx in ipairs(contexts) do
    table.insert(lines, ("### %s — `<leader>%s`"):format(ctx.name, ctx.prefix))
    table.insert(lines, "")
    table.insert(lines, "_Dónde: " .. where(ctx) .. "_")
    table.insert(lines, "")
    table.insert(lines, "| Tecla | Acción |")
    table.insert(lines, "|---|---|")
    for _, m in ipairs(ctx.maps) do
      table.insert(lines, ("| `<leader>%s%s` | %s |"):format(ctx.prefix, m[1], cell(m[2])))
    end
    table.insert(lines, "")
  end
end

---@param lines string[]
local function render_lsp(lines)
  table.insert(lines, "## LSP (al adjuntar un servidor)")
  table.insert(lines, "")
  table.insert(lines, "Keymaps buffer-locales de `servers/on_attach.lua`.")
  table.insert(lines, "")
  table.insert(lines, "| Tecla | Acción |")
  table.insert(lines, "|---|---|")
  for _, m in ipairs(require("servers.on_attach").keymaps()) do
    table.insert(lines, ("| `%s` | %s |"):format(pretty_lhs(m[1]), cell((m[3]:gsub("^LSP ", "")))))
  end
  table.insert(lines, "")
end

--- Teclas del buffer de nvim-tree (defaults + las de plugins/navigation/nvim-tree.lua),
--- leídas abriendo el árbol de verdad.
---@param lines string[]
local function render_tree(lines)
  local ok, api = pcall(require, "nvim-tree.api")
  if not ok then
    return table.insert(M.warnings, "nvim-tree no disponible: sección omitida")
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
    return table.insert(M.warnings, "nvim-tree sin keymaps: sección omitida")
  end
  table.sort(maps, function(a, b)
    return a[1] < b[1]
  end)
  table.insert(lines, "## nvim-tree (dentro del árbol)")
  table.insert(lines, "")
  table.insert(lines, "`Ctrl+n` lo abre/cierra y `<leader>e` lo enfoca (ver Atajos globales). `g?` dentro del árbol lista estas mismas teclas.")
  table.insert(lines, "")
  table.insert(lines, "| Tecla | Acción |")
  table.insert(lines, "|---|---|")
  for _, m in ipairs(maps) do
    table.insert(lines, ("| `%s` | %s |"):format(m[1], cell(m[2])))
  end
  table.insert(lines, "")
end

-- Vocabulario de comandos de blink.cmp (nombres fijos de la librería)
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

--- Autocompletado: preset + overrides de plugins/editing/blink.lua (modo insert)
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
            table.insert(parts, "custom hook (Go `ErrX` ghost text, `utils/goerrors`)")
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

    table.insert(lines, "## Autocompletado (blink.cmp, modo insert)")
    table.insert(lines, "")
    table.insert(lines, "Preset `" .. (opts.keymap.preset or "default") .. "` más los overrides de `plugins/editing/blink.lua`. `→` = se prueba en orden hasta que uno aplica.")
    table.insert(lines, "")
    table.insert(lines, "| Tecla | Acción |")
    table.insert(lines, "|---|---|")
    for _, r in ipairs(rows) do
      table.insert(lines, ("| `%s` | %s |"):format(r[1], cell(r[2])))
    end
    table.insert(lines, "")
  end)
  if not ok then
    table.insert(M.warnings, "blink.cmp: sección omitida (" .. tostring(err) .. ")")
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
    "<!-- GENERADO por scripts/gen-cheatsheet.sh — NO editar a mano. -->",
    "",
    "> Generado desde los keymaps reales de la config (`nvim_get_keymap`, `menus/`, `servers/on_attach.lua`).",
    "> Se regenera solo en cada commit (`.githooks/pre-commit`). `<leader>` = `Space`.",
    "> Esta es la ÚNICA fuente de teclas. Lo que no se deriva del código (qué hace cada cosa, flujos, herramientas): [`docs/cheatsheets/`](docs/cheatsheets/README.md).",
    "",
  }

  render_menus(lines)
  render_lsp(lines)
  render_blink(lines)
  render_tree(lines)

  table.insert(lines, "## Atajos globales")
  table.insert(lines, "")
  table.insert(lines, "Secciones = primera palabra del `desc` (igual que el botón **Mappings** del dashboard).")
  table.insert(lines, "")
  for _, name in ipairs(names) do
    table.insert(lines, "### " .. name)
    table.insert(lines, "")
    section_table(lines, sections[name])
  end

  table.insert(lines, "## Nativos de Neovim 0.11 (no son de esta config)")
  table.insert(lines, "")
  table.insert(lines, "| Tecla | Acción |")
  table.insert(lines, "|---|---|")
  for _, r in ipairs {
    { "grn", "renombrar símbolo" },
    { "gra", "code action" },
    { "gri", "ir a la implementación" },
    { "grt", "ir a la definición del tipo" },
    { "gO", "símbolos del documento" },
    { "K", "hover (documentación)" },
    { "gx", "abrir la URL o ruta bajo el cursor" },
    { "gc / gcc", "comentar (operador / línea)" },
  } do
    table.insert(lines, ("| `%s` | %s |"):format(r[1], r[2]))
  end
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

--- Espera a que los keymaps de arranque existan (NvChad los carga con vim.schedule) y
--- dispara VeryLazy, que en headless no llega solo (no hay UIEnter): así los plugins que
--- mapean al cargar (mini.move...) quedan igual que en una sesión real.
---@return boolean
function M.wait_ready()
  local ready = vim.wait(10000, function()
    return vim.fn.maparg(" ff", "n") ~= "" and vim.fn.maparg("s", "n") ~= ""
  end, 50)
  vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
  vim.wait(200)
  return ready
end

--- Escribe el cheatsheet; con `check` solo compara y devuelve false si difiere
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
