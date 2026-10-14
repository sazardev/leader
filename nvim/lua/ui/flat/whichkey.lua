-- ── Flat design: the which-key panel ─────────────────────────────────────────
-- which-key drawn like the landing page's demo: a soft panel across the whole width right above the statusline,
-- entries in a grid of 4 equal columns filled ROW by row (`key ➜ description`, groups first as purple `+Group`),
-- a half-cell top edge instead of a blank row, and one faint footer row: `Space » +Find` left, `Esc close · BS back`
-- right. Replaces which-key's view.show (its own layout fills columns top to bottom and centers the help).
-- `grid` is pure (tested in scripts/test-flat.sh).
local M = {}

local WIDE = 100 -- from this many columns the grid has 4 columns, below it 2 (the demo's breakpoint)
local PAD = 2 -- columns of air at each side of the panel (the demo's 16px)
local GAP = 2 -- columns between grid cells (the demo's 18px)

---@class FlatWkItem
---@field key string
---@field desc string
---@field group boolean

--- Row-major grid: `items` in rows of `n`, each cell `key ➜ desc` cut to its width.
--- Returns one list of `{ text, hl }` chunks per row.
---@param items FlatWkItem[]
---@param width integer panel width
---@return table[][] rows, integer n columns
function M.grid(items, width)
  local n = width >= WIDE and 4 or 2
  local cell = math.floor((width - 2 * PAD) / n)
  local rows = {}
  for i, it in ipairs(items) do
    local r = math.floor((i - 1) / n) + 1
    rows[r] = rows[r] or { { (" "):rep(PAD) } }
    local room = cell - GAP - vim.fn.strdisplaywidth(it.key) - 3
    local desc = it.desc
    if vim.fn.strdisplaywidth(desc) > room then
      desc = vim.fn.strcharpart(desc, 0, math.max(room - 1, 1)) .. "…"
    end
    local used = vim.fn.strdisplaywidth(it.key) + 3 + vim.fn.strdisplaywidth(desc)
    local chunks = rows[r]
    chunks[#chunks + 1] = { it.key, "WhichKey" }
    chunks[#chunks + 1] = { " ➜ ", "WhichKeySeparator" }
    chunks[#chunks + 1] = { desc, it.group and "WhichKeyGroup" or "WhichKeyDesc" }
    chunks[#chunks + 1] = { (" "):rep(math.max(cell - used, GAP)) }
  end
  return rows, n
end

--- `Space » +Find » +Agent`: where you are, like the demo's breadcrumb
---@param node table which-key node
---@return string
function M.crumb(node)
  local view = require "which-key.view"
  local parts = {}
  while node and node.parent do
    local label = node.desc and ("+" .. node.desc) or vim.trim(view.format(node.key))
    table.insert(parts, 1, label)
    node = node.parent
  end
  return table.concat(parts, " » ")
end

--- Groups first, then keys in natural order (a C f g G h …), like the demo's menus
local function group_first(item)
  return item.group and 0 or 1
end

function M.show()
  local view = require "which-key.view"
  local State = require "which-key.state"
  local Config = require "which-key.config"
  local Win = require "which-key.win"
  local Text = require "which-key.text"

  local state = State.state
  if not (state and state.show and state.node:is_group()) then
    view.hide()
    return
  end

  -- the same filter/expand which-key's own view applies
  if state.filter.global == false and state.filter.expand == nil then
    state.filter.expand = true
  end
  local function filter(node)
    local l, g = state.filter["local"] ~= false, state.filter.global ~= false
    if not g and not l then
      return false
    end
    if g and l then
      return true
    end
    local is_local = node:is_local()
    return l and is_local or g and not is_local
  end
  local function expand(node)
    if node:is_plugin() then
      return false
    end
    if state.filter.expand then
      return true
    end
    if node:can_expand() then
      return false
    end
    if type(Config.expand) == "function" then
      return Config.expand(node)
    end
    local count = node:count()
    return count > 0 and count <= Config.expand
  end

  local items = {}
  for _, node in ipairs(state.node:children()) do
    vim.list_extend(items, view.expand(state.node, node, expand, filter))
  end
  -- a key that is an action AND the prefix of hidden keymaps only (Space w: save; w K, w k hidden) reads as an action
  for _, it in ipairs(items) do
    if it.group and it.node.keymap then
      local visible = false
      for _, child in pairs(it.node:children()) do
        visible = visible or not (child.mapping and child.mapping.hidden)
      end
      if not visible then
        it.group = false
        it.desc = it.desc:gsub("^%+", "")
      end
    end
  end
  view.sort(items, { "order", group_first })

  local width = vim.o.columns
  local rows = M.grid(items, width)
  local text = Text.new()
  text:append(("▄"):rep(width), "WhichKeyEdge")
  for _, chunks in ipairs(rows) do
    text:nl()
    for _, c in ipairs(chunks) do
      text:append(c[1], c[2])
    end
  end
  -- footer: breadcrumb left, the keys that close or go back right; all faint
  local help = "Esc close · BS back" .. (" "):rep(PAD)
  local crumb = (" "):rep(PAD) .. M.crumb(state.node)
  text:nl()
  text:append(crumb, "WhichKeySeparator")
  text:append((" "):rep(math.max(width - vim.fn.strdisplaywidth(crumb) - vim.fn.strdisplaywidth(help), 1)))
  text:append(help, "WhichKeySeparator")

  local height = #rows + 2
  local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus ~= 0 and 1 or 0)
  local opts = {
    relative = "editor",
    row = math.max(bottom - height, 0),
    col = 0,
    width = width,
    height = math.min(height, bottom),
    border = "none",
    zindex = 1000,
  }
  if view.footer then
    view.footer:hide()
    view.footer = nil
  end
  local fresh = not view.view
  if not view.view then
    view.view = Win.new(vim.tbl_deep_extend("force", Win.defaults(Config.win), opts))
    -- which-key's own title/footer/padding settings mean nothing for a borderless panel
    view.view.opts.title, view.view.opts.title_pos, view.view.opts.footer, view.view.opts.footer_pos =
      nil, nil, nil, nil
  end
  view.view:show(opts)
  text:render(view.view.buf)
  vim.api.nvim_win_call(view.view.win, function()
    vim.fn.winrestview { topline = 1 }
  end)
  if fresh then
    require("ui.flat.motion").enter({ view.view.win }, 2) -- slides up from the statusline (the demo's)
  end
  vim.cmd.redraw()
end

--- Makes which-key draw with `M.show`. Idempotent.
function M.install()
  local view = require "which-key.view"
  if view._flat_show then
    return
  end
  view._flat_show = true
  view.show = M.show
end

return M
