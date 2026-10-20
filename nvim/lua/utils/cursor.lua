-- ── Hiding the cursor where a page draws its own selection ───────────────────
-- The start screen, the menus, the full-screen lists and the setup each hide the terminal cursor while they are on
-- screen. Each used to save and restore `guicursor` by itself: opened over one another, whichever closed last put back
-- the value that was already hidden, and the cursor stayed invisible everywhere. Now there is ONE owner list: the real
-- `guicursor` is saved when the first owner hides it and put back when the last one lets go, and anything that is
-- not the real thing (a value that already names NvStartCursor) is never taken as the real thing.
--
--   hide(owner, "nv")   hides it in normal and visual mode only (a list with a filter prompt still shows it typing)
--   hide(owner)         hides it in every mode
--   show(owner)         this owner is done
local M = {}

M.HIDDEN = "NvStartCursor"
M.DEFAULT = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,a:blinkwait700-blinkoff400-blinkon250"

local owners = {} ---@type table<any, "all"|"nv">
local saved ---@type string?

local function count()
  return vim.tbl_count(owners)
end

---@param value string
---@return boolean
function M.is_hidden(value)
  return value:find(M.HIDDEN, 1, true) ~= nil
end

local function apply()
  if count() == 0 then
    if saved then
      vim.o.guicursor, saved = saved, nil
    end
    return
  end
  local all = vim.iter(owners):any(function(_, mode)
    return mode == "all"
  end)
  vim.o.guicursor = all and ("a:" .. M.HIDDEN) or (saved .. ",n-v:" .. M.HIDDEN)
end

---@param owner any
---@param mode "all"|"nv"|nil
function M.hide(owner, mode)
  if count() == 0 then
    local now = vim.o.guicursor
    saved = (now ~= "" and not M.is_hidden(now)) and now or M.DEFAULT
  end
  owners[owner] = mode == "nv" and "nv" or "all"
  apply()
end

---@param owner any
function M.show(owner)
  if owners[owner] then
    owners[owner] = nil
    apply()
  end
end

--- Safety net: nothing owns the hidden cursor but it is hidden anyway (a bug elsewhere, a reloaded config): back to normal.
function M.repair()
  if count() == 0 and M.is_hidden(vim.o.guicursor) then
    vim.o.guicursor = saved or M.DEFAULT
    saved = nil
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "ModeChanged" }, {
    group = vim.api.nvim_create_augroup("CursorRepair", { clear = true }),
    callback = function()
      vim.schedule(M.repair)
    end,
  })
end

--- Tests: forget every owner.
function M.reset()
  owners, saved = {}, nil
end

return M
