-- ── Contextual leader menus ──────────────────────────────────────────────────
-- Each context (language or git) lives under its own <leader> letter and ONLY
-- exists in the buffers where it applies (buffer-local keymaps + which-key
-- group). The <leader> popup shows only what is relevant.
--
-- A context is: { name, prefix, maps = { {key, desc, fn, modes?}... },
--                 filetypes? = {...}, detect? = fun(buf): boolean,
--                 groups? = { [letter] = name } (names of sub-prefixes inside the menu) }
local M = {}

---@return table[]
function M.contexts()
  local list = require("languages").menus()
  table.insert(list, require "menus.git")
  table.insert(list, require "menus.settings")
  table.insert(list, require "menus.files")
  table.insert(list, require "menus.session")
  table.insert(list, require "menus.history")
  table.insert(list, require "menus.tasks")
  table.insert(list, require "menus.agent")
  table.insert(list, require "menus.agent_advanced")
  table.insert(list, require "menus.agent_ddd")
  table.insert(list, require "menus.agent_repository")
  table.insert(list, require "menus.agent_service")
  table.insert(list, require "menus.agent_doctor")
  table.insert(list, require "menus.agent_setup")
  table.insert(list, require "menus.agent_tests")
  table.insert(list, require "menus.agent_lenses")
  table.insert(list, require "menus.comments")
  table.insert(list, require "menus.folds")
  return list
end

--- `desc` an action is registered with. It starts with the first word of the
--- menu name ("Go run", "Git status"): NvCheatsheet (the dashboard's Mappings button)
--- groups by the first word of the desc, and requires at least two.
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
    -- optional 4th element: mapping modes (normal only by default; SQL runs a visual selection)
    vim.keymap.set(m[4] or "n", "<leader>" .. ctx.prefix .. m[1], m[3], { buffer = buf, desc = M.desc(ctx, m[2]) })
  end
  -- group name in which-key, only for this buffer
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add { { "<leader>" .. ctx.prefix, group = ctx.name, buffer = buf } }
    -- optional sub-groups: keys of a context that start with one letter and go on (`<leader>gS` + l, a, d…)
    for key, name in pairs(ctx.groups or {}) do
      wk.add { { "<leader>" .. ctx.prefix .. key, group = name, buffer = buf } }
    end
  end
end

--- Global context: registered only once, without a buffer
---@param ctx table
local function bind_global(ctx)
  for _, m in ipairs(ctx.maps) do
    -- optional 4th element: mapping modes (normal only by default)
    vim.keymap.set(m[4] or "n", "<leader>" .. ctx.prefix .. m[1], m[3], { desc = M.desc(ctx, m[2]) })
  end
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add { { "<leader>" .. ctx.prefix, group = ctx.name, mode = { "n", "x" } } }
    for key, name in pairs(ctx.groups or {}) do
      wk.add { { "<leader>" .. ctx.prefix .. key, group = name, mode = { "n", "x" } } }
    end
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

  -- keymaps are loaded with vim.schedule: the initial buffer's events have already passed
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      attach(buf)
    end
  end
end

return M
