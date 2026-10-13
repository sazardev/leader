-- ── Menús contextuales del leader ────────────────────────────────────────────
-- Cada contexto (lenguaje o git) vive bajo su propia letra de <leader> y SOLO
-- existe en los buffers donde aplica (keymaps + grupo de which-key
-- buffer-locales). El popup de <leader> muestra únicamente lo relevante.
--
-- Un contexto es: { name, prefix, maps = { {key, desc, fn, modes?}... },
--                   filetypes? = {...}, detect? = fun(buf): boolean }
local M = {}

---@return table[]
function M.contexts()
  local list = require("languages").menus()
  table.insert(list, require "menus.git")
  table.insert(list, require "menus.settings")
  table.insert(list, require "menus.session")
  table.insert(list, require "menus.agent")
  table.insert(list, require "menus.agent_ddd")
  table.insert(list, require "menus.agent_repository")
  table.insert(list, require "menus.agent_service")
  table.insert(list, require "menus.comments")
  return list
end

--- `desc` con el que se registra una acción. Empieza por la primera palabra del
--- nombre del menú ("Go run", "Git status"): NvCheatsheet (botón Mappings del
--- dashboard) agrupa por la primera palabra del desc, y exige al menos dos.
---@param ctx table
---@param text string
---@return string
function M.desc(ctx, text)
  return ctx.name:match "%S+" .. " " .. text
end

---@param buf integer
---@param ctx table
local function bind(buf, ctx)
  local seen = vim.b[buf].menu_contexts or {}
  if seen[ctx.prefix] == ctx.name then
    return
  end
  seen[ctx.prefix] = ctx.name
  vim.b[buf].menu_contexts = seen

  for _, m in ipairs(ctx.maps) do
    vim.keymap.set("n", "<leader>" .. ctx.prefix .. m[1], m[3], { buffer = buf, desc = M.desc(ctx, m[2]) })
  end
  -- nombre del grupo en which-key, solo para este buffer
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add { { "<leader>" .. ctx.prefix, group = ctx.name, buffer = buf } }
  end
end

--- Contexto global: se registra una sola vez, sin buffer
---@param ctx table
local function bind_global(ctx)
  for _, m in ipairs(ctx.maps) do
    -- 4º elemento opcional: modos del mapeo (por defecto solo normal)
    vim.keymap.set(m[4] or "n", "<leader>" .. ctx.prefix .. m[1], m[3], { desc = M.desc(ctx, m[2]) })
  end
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add { { "<leader>" .. ctx.prefix, group = ctx.name, mode = { "n", "x" } } }
  end
end

---@param ctx table
---@param buf integer
---@return boolean
local function applies(ctx, buf)
  if ctx.global then
    return false
  end
  if ctx.detect then
    return ctx.detect(buf)
  end
  return vim.tbl_contains(ctx.filetypes or {}, vim.bo[buf].filetype)
end

function M.setup()
  local list = M.contexts()

  for _, ctx in ipairs(list) do
    if ctx.global then
      bind_global(ctx)
    end
  end

  local function attach(buf)
    for _, ctx in ipairs(list) do
      if applies(ctx, buf) then
        bind(buf, ctx)
      end
    end
  end

  local group = vim.api.nvim_create_augroup("MenuContexts", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufReadPost", "BufNewFile", "BufFilePost" }, {
    group = group,
    callback = function(args)
      attach(args.buf)
    end,
  })

  -- los keymaps se cargan con vim.schedule: los eventos del buffer inicial ya pasaron
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      attach(buf)
    end
  end
end

return M
