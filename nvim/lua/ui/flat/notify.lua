-- ── Flat notifications ───────────────────────────────────────────────────────
-- Replaces `vim.notify`: a small filled block at the bottom right, a colored bar on the left (green info,
-- yellow warning, red error), stacked and fading away by itself. It reads like the demo's notes. No plugin: floats
-- that are never focused, so they never take a key. Without a UI (headless, scripts) it keeps the original `vim.notify`.
local M = {}

local MAX_WIDTH = 56
local ns = vim.api.nvim_create_namespace "FlatNotify"
local LEVELS = {
  [vim.log.levels.TRACE] = { hl = "FlatNotifyDebug", ms = 3000 },
  [vim.log.levels.DEBUG] = { hl = "FlatNotifyDebug", ms = 3000 },
  [vim.log.levels.INFO] = { hl = "FlatNotifyInfo", ms = 3500 },
  [vim.log.levels.WARN] = { hl = "FlatNotifyWarn", ms = 6000 },
  [vim.log.levels.ERROR] = { hl = "FlatNotifyError", ms = 8000 },
}

local stack = {} ---@type { win: integer, height: integer }[]
local original ---@type function

--- Word-wraps `text` to `width` display columns
---@param text string
---@param width integer
---@return string[]
local function wrap(text, width)
  local rows = {}
  for paragraph in (text .. "\n"):gmatch "(.-)\n" do
    local row = ""
    for word in paragraph:gmatch "%S+" do
      while vim.fn.strdisplaywidth(word) > width do
        if row ~= "" then
          rows[#rows + 1] = row
          row = ""
        end
        rows[#rows + 1] = vim.fn.strcharpart(word, 0, width)
        word = vim.fn.strcharpart(word, width)
      end
      if row == "" then
        row = word
      elseif vim.fn.strdisplaywidth(row .. " " .. word) <= width then
        row = row .. " " .. word
      else
        rows[#rows + 1] = row
        row = word
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

--- Puts every live notification in its place: from the bottom up, above the statusline
local function layout()
  local live = {}
  for _, n in ipairs(stack) do
    if vim.api.nvim_win_is_valid(n.win) then
      live[#live + 1] = n
    end
  end
  stack = live
  local row = vim.o.lines - 1 -- bottom edge: right above the global statusline
  for i = #stack, 1, -1 do
    local n = stack[i]
    vim.api.nvim_win_set_config(n.win, { relative = "editor", anchor = "SE", row = row, col = vim.o.columns })
    row = row - n.height - 1
  end
end

local function close(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  layout()
end

--- Moves 'winblend' of `win` from one value to another in a few steps (the fade of the demo's notes)
---@param win integer
---@param from integer
---@param to integer
---@param done? fun()
local function fade(win, from, to, done)
  local steps, step = 5, 0
  local timer = vim.uv.new_timer()
  timer:start(
    0,
    22,
    vim.schedule_wrap(function()
      step = step + 1
      if not vim.api.nvim_win_is_valid(win) then
        timer:stop()
        timer:close()
        return
      end
      vim.wo[win].winblend = math.floor(from + (to - from) * step / steps)
      if step >= steps then
        timer:stop()
        timer:close()
        if done then
          done()
        end
      end
    end)
  )
end

---@param msg any
---@param level? integer
---@param opts? { title?: string, timeout?: integer }
function M.notify(msg, level, opts)
  if #vim.api.nvim_list_uis() == 0 then
    return original(msg, level, opts)
  end
  if vim.in_fast_event() then
    return vim.schedule(function()
      M.notify(msg, level, opts)
    end)
  end
  opts = opts or {}
  local kind = LEVELS[level or vim.log.levels.INFO] or LEVELS[vim.log.levels.INFO]
  local rows = wrap(tostring(msg), MAX_WIDTH)
  if opts.title then
    table.insert(rows, 1, opts.title)
  end
  local width = 0
  for i, r in ipairs(rows) do
    rows[i] = " " .. r .. " " -- air on both sides of the text
    width = math.max(width, vim.fn.strdisplaywidth(rows[i]))
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 1,
    col = vim.o.columns,
    width = width,
    height = #rows,
    style = "minimal",
    border = { "", "", "", "", "", "", "", "▌" }, -- the left bar IS the border: only the left column, colored per level
    focusable = false,
    noautocmd = true,
    zindex = 250,
  })
  if not ok then
    return original(msg, level, opts)
  end
  vim.wo[win].winhighlight = ("NormalFloat:FlatNotify,FloatBorder:%s"):format(kind.hl)
  vim.wo[win].winblend = 100
  fade(win, 100, 0)
  if opts.title then
    vim.api.nvim_buf_set_extmark(
      buf,
      ns,
      0,
      0,
      { end_row = 1, end_col = 0, hl_group = "FlatNotifyTitle", hl_eol = true }
    )
  end
  stack[#stack + 1] = { win = win, height = #rows }
  layout()
  vim.defer_fn(function()
    fade(win, 0, 100, function()
      close(win)
    end)
  end, opts.timeout or kind.ms)
end

--- Closes every notification
function M.dismiss()
  for _, n in ipairs(stack) do
    if vim.api.nvim_win_is_valid(n.win) then
      vim.api.nvim_win_close(n.win, true)
    end
  end
  stack = {}
end

function M.setup()
  if original then
    return
  end
  original = vim.notify
  vim.notify = M.notify
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("FlatNotify", { clear = true }),
    callback = layout,
  })
end

return M
