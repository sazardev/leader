-- ── Trigger selector (UI only) ──────────────────────────────────────────────
-- The floating list under the input cursor: draw, move, hide. It never decides
-- what to show or what accepting means (completion.lua does).
local trigger = require "agent.chat.trigger"

local M = {}

---@class ChatPopup
---@field win integer?
---@field buf integer?
---@field items table[]
---@field sel integer
---@field kind string
local P = { items = {}, sel = 1 }

---@return boolean
function M.is_visible()
  return P.win ~= nil and vim.api.nvim_win_is_valid(P.win)
end

---@return table?
function M.selected()
  return P.items[P.sel]
end

function M.hide()
  if P.win and vim.api.nvim_win_is_valid(P.win) then
    vim.api.nvim_win_close(P.win, true)
  end
  P.win, P.buf, P.items, P.sel, P.anchor = nil, nil, {}, 1, nil
end

---@return string? kind
function M.kind()
  return M.is_visible() and P.kind or nil
end

---@param delta integer
function M.move(delta)
  if not M.is_visible() or #P.items == 0 then
    return
  end
  P.sel = ((P.sel - 1 + delta) % #P.items) + 1
  M.render()
end

local function label(kind, item)
  return trigger.sign(kind) .. item.value
end

function M.render()
  if not (P.buf and vim.api.nvim_buf_is_valid(P.buf)) then
    return
  end
  local lines = {}
  for _, item in ipairs(P.items) do
    local text = " " .. label(P.kind, item)
    if item.desc and item.desc ~= "" then
      text = text .. string.rep(" ", math.max(2, 36 - vim.fn.strdisplaywidth(text))) .. item.desc
    end
    lines[#lines + 1] = text
  end
  vim.bo[P.buf].modifiable = true
  vim.api.nvim_buf_set_lines(P.buf, 0, -1, false, lines)
  vim.bo[P.buf].modifiable = false
  local ns = vim.api.nvim_create_namespace "chat.complete"
  vim.api.nvim_buf_clear_namespace(P.buf, ns, 0, -1)
  for i, item in ipairs(P.items) do
    if i == P.sel then
      vim.api.nvim_buf_set_extmark(P.buf, ns, i - 1, 0, {
        end_row = i,
        end_col = 0,
        hl_group = "ChatHeader",
        hl_eol = true,
      })
    else
      local name = label(P.kind, item)
      vim.api.nvim_buf_set_extmark(P.buf, ns, i - 1, 1, { end_col = 1 + #name, hl_group = "ChatUserIcon" })
    end
  end
  if P.win and vim.api.nvim_win_is_valid(P.win) then
    local widest = 24
    for _, l in ipairs(lines) do
      widest = math.max(widest, vim.fn.strdisplaywidth(l))
    end
    pcall(vim.api.nvim_win_set_config, P.win, {
      relative = "win",
      win = P.anchor and P.anchor.win or nil,
      bufpos = P.anchor and { P.anchor.row - 1, P.anchor.col } or nil,
      height = math.max(1, math.min(#lines, 10)),
      width = math.min(72, widest + 1),
    })
  end
end

--- Creates the window the first time and updates it afterwards.
---@param kind string
---@param items table[]
---@param anchor { win: integer, row: integer, col: integer }
function M.show(kind, items, anchor)
  P.kind = kind
  P.items = items
  P.anchor = anchor
  if P.sel > #items then
    P.sel = 1
  end
  if not (P.buf and vim.api.nvim_buf_is_valid(P.buf)) then
    P.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[P.buf].bufhidden = "hide"
    vim.bo[P.buf].modifiable = false
    vim.bo[P.buf].filetype = "leaderchat_complete"
    vim.diagnostic.enable(false, { bufnr = P.buf })
  end
  if P.win and vim.api.nvim_win_is_valid(P.win) then
    pcall(vim.api.nvim_win_set_config, P.win, {
      relative = "win",
      win = anchor.win,
      bufpos = { anchor.row - 1, anchor.col },
      height = math.max(1, math.min(#items, 10)),
    })
    M.render()
    return
  end
  local widest = 24
  for _, item in ipairs(items) do
    local text = label(kind, item)
    widest = math.max(widest, #text + 1 + (item.desc ~= "" and (#item.desc + 1) or 0))
  end
  local ok, opened = pcall(vim.api.nvim_open_win, P.buf, false, {
    relative = "win",
    win = anchor.win,
    bufpos = { anchor.row - 1, anchor.col },
    anchor = "NW",
    width = math.min(72, widest + 1),
    height = math.max(1, math.min(#items, 10)),
    style = "minimal",
    border = require("ui.flat").border(),
    title = { { " " .. trigger.label(kind) .. " ", "ChatHeader" } },
    title_pos = "left",
    focusable = false,
    zindex = 60,
  })
  if not ok then
    return M.hide()
  end
  P.win = opened
  vim.w[P.win].leader_keep = true
  vim.wo[P.win].winhighlight = "NormalFloat:ChatFloat,Normal:ChatFloat,FloatBorder:ChatBorder,FloatTitle:ChatHeader"
  M.render()
  pcall(require("ui.flat.motion").enter, { P.win }, 1)
end

return M
