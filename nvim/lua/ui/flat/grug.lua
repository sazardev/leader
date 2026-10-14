-- ── Flat design: grug-far ────────────────────────────────────────────────────
-- grug-far drawn like the landing page's "Replace in project": a soft panel with a `Grug FAR` header (`g? help` on the
-- right), every input a `deep` bar (its aqua label inside, from grug-far's compact inputs), then the results.
local M = {}

local NS = vim.api.nvim_create_namespace "FlatGrug"
-- the inputs, in grug-far's order: with compact inputs each one is a row at the top of the buffer
local LABELS = { "Search:", "Replace:", "Files Filter:", "Flags:", "Paths:" }
local LABEL_WIDTH = 14 -- the demo's 14ch label column

--- The input rows: a `deep` bar each with its label inside, aqua, in a column of its own
---@param buf integer
local function paint(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  local count = math.min(#LABELS, vim.api.nvim_buf_line_count(buf))
  for row = 0, count - 1 do
    local label = " " .. LABELS[row + 1]
    vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
      line_hl_group = "GrugFarInput",
      virt_text = { { label .. (" "):rep(LABEL_WIDTH - #label), "GrugFarInputLabel" } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end
end

---@param win integer
local function dress(win)
  vim.wo[win].winhighlight =
    "Normal:GrugFarNormal,NormalNC:GrugFarNormal,EndOfBuffer:GrugFarNormal,SignColumn:GrugFarNormal,WinBar:GrugFarHeader,WinBarNC:GrugFarHeader"
  vim.wo[win].winbar = "%#GrugFarHeader# Grug FAR%=%#GrugFarHelpHeader#g? help "
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].statuscolumn = ""
  vim.wo[win].foldcolumn = "0"
end

function M.setup()
  local group = vim.api.nvim_create_augroup("FlatGrug", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "grug-far",
    callback = function(ev)
      local buf = ev.buf
      vim.schedule(function()
        local win = vim.fn.bufwinid(buf)
        if win ~= -1 then
          dress(win)
        end
        paint(buf)
      end)
      vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWinEnter" }, {
        group = group,
        buffer = buf,
        callback = function()
          local win = vim.fn.bufwinid(buf)
          if win ~= -1 then
            dress(win)
          end
          paint(buf)
        end,
      })
    end,
  })
end

return M
