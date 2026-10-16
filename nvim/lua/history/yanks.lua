-- ── Yank history ─────────────────────────────────────────────────────────────
-- Every yank and cut (TextYankPost), newest first, without duplicates (yanking a text again moves it to the top).
-- Right after `p`/`P`, `[y` swaps what was pasted for the previous entry and `]y` for the next one; `<leader>uy`
-- lists them all. Kept in memory and written to stdpath("state")/yanks.json on exit (`settings.history.yanks`).
-- Nothing is read until the first yank, paste or list.
local M = {}

---@class HistoryYank
---@field lines string[]
---@field type string regtype: "v", "V" or "\22{width}"
---@field time integer
---@field ft string? filetype it came from (the list's preview highlights it)

---@return table
local function opts()
  return (require("core.settings").history or {}).yanks or {}
end

---@return string
function M.path()
  return vim.fn.stdpath "state" .. "/yanks.json"
end

---@param a string[]
---@param b string[]
---@return boolean
local function same(a, b)
  return table.concat(a, "\n") == table.concat(b, "\n")
end

--- Pure: `entry` goes on top of `list` (an equal text already there moves up), at most `max` entries.
--- Blank texts (a deleted empty line, a space) are not worth keeping.
---@param list HistoryYank[]
---@param entry HistoryYank
---@param max integer
---@param max_chars integer?
---@return HistoryYank[]
function M.push(list, entry, max, max_chars)
  local text = table.concat(entry.lines, "\n")
  if not text:find "%S" or (max_chars and #text > max_chars) then
    return list
  end
  local out = { entry }
  for _, e in ipairs(list) do
    if #out >= max then
      break
    end
    if not same(e.lines, entry.lines) then
      out[#out + 1] = e
    end
  end
  return out
end

--- Pure: position of `lines` in `list` (nil if it is not there)
---@param list HistoryYank[]
---@param lines string[]
---@return integer?
function M.find(list, lines)
  for i, e in ipairs(list) do
    if same(e.lines, lines) then
      return i
    end
  end
end

--- Pure: one line describing an entry (first non-blank line, how many more)
---@param entry HistoryYank
---@return string
function M.label(entry)
  local first, n = "", #entry.lines
  for _, l in ipairs(entry.lines) do
    if l:find "%S" then
      first = vim.trim(l)
      break
    end
  end
  return n > 1 and ("%s  (+%d lines)"):format(first, n - 1) or first
end

local list ---@type HistoryYank[]?
local dirty = false

---@return HistoryYank[]?
local function read_disk()
  local fd = io.open(M.path(), "r")
  if not fd then
    return nil
  end
  local ok, data = pcall(vim.json.decode, fd:read "*a")
  fd:close()
  return ok and type(data) == "table" and data or nil
end

---@return HistoryYank[]
function M.list()
  if not list then
    list = opts().persist ~= false and read_disk() or {}
  end
  return list
end

---@param entry HistoryYank
function M.add(entry)
  local o = opts()
  list = M.push(M.list(), entry, o.max or 50, o.max_chars)
  dirty = true
end

---@param index integer
function M.remove(index)
  table.remove(M.list(), index)
  dirty = true
end

--- Writes the list (merged with what another nvim saved meanwhile, ours first; `replace` writes it as it is)
---@param replace boolean?
function M.save(replace)
  if not dirty or opts().persist == false then
    return
  end
  local o, merged = opts(), M.list()
  for _, e in ipairs(not replace and read_disk() or {}) do
    if #merged >= (o.max or 50) then
      break
    end
    if not M.find(merged, e.lines) then
      merged[#merged + 1] = e
    end
  end
  vim.fn.mkdir(vim.fs.dirname(M.path()), "p")
  local fd = io.open(M.path(), "w")
  if fd then
    fd:write(vim.json.encode(merged))
    fd:close()
  end
  dirty = false
end

--- Forgets every entry, on disk too (saving later would merge them back)
function M.clear()
  list, dirty = {}, true
  M.save(true)
end

function M.on_yank()
  local ev = vim.v.event
  M.add { lines = ev.regcontents, type = ev.regtype, time = os.time(), ft = vim.bo.filetype }
end

-- ── Paste and cycle ─────────────────────────────────────────────────────────
-- What the last `p`/`P` pasted, to swap it while nothing else changed the buffer
local last ---@type { buf: integer, tick: integer, key: string, count: integer, reg: string, index: integer? }?

--- Flashes what was just pasted ('[ to '])
---@param regtype string
local function flash(regtype)
  if not require("ui.flat").enabled() then
    return
  end
  local s, e = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
  if s[1] == 0 then
    return
  end
  local fresh = require "ui.flat.fresh"
  if regtype == "v" then
    fresh.range(0, s[1] - 1, s[2], e[1] - 1, e[2] + 1)
  else
    fresh.lines(0, s[1] - 1, e[1])
  end
end

--- `p` / `P` as usual (register and count included), remembered so `[y`/`]y` can swap it
---@param key "p"|"P"
function M.paste(key)
  return function()
    local reg, count = vim.v.register, vim.v.count1
    local ok, err = pcall(vim.cmd, ('normal! %d"%s%s'):format(count, reg, key))
    if not ok then
      return vim.notify((tostring(err):gsub("^.-:%s*", "")), vim.log.levels.WARN)
    end
    local buf = vim.api.nvim_get_current_buf()
    last = { buf = buf, tick = vim.b[buf].changedtick, key = key, count = count, reg = reg }
    flash(vim.fn.getregtype(reg))
  end
end

--- Pastes `entry` without touching any register the user sees (a borrowed `z`, restored at once)
---@param entry HistoryYank
---@param key "p"|"P"
---@param count integer
function M.put(entry, key, count)
  local saved = vim.fn.getreginfo "z"
  vim.fn.setreg("z", entry.lines, entry.type)
  pcall(vim.cmd, ('normal! %d"z%s'):format(count, key))
  vim.fn.setreg("z", saved)
  flash(entry.type)
end

--- Swaps what was just pasted for an older (1) or newer (-1) entry of the history
---@param dir 1|-1
function M.cycle(dir)
  local buf = vim.api.nvim_get_current_buf()
  if not last or last.buf ~= buf or vim.b[buf].changedtick ~= last.tick then
    return vim.api.nvim_echo({ { "[y / ]y swap the text you just pasted (paste with p first)" } }, false, {})
  end
  local items = M.list()
  if not last.index then
    last.index = M.find(items, vim.fn.getreg(last.reg, 1, true) --[[@as string[] ]]) or 0
  end
  local i = last.index + dir
  if i < 1 or i > #items then
    return vim.api.nvim_echo({ { dir > 0 and "No older yank" or "No newer yank" } }, false, {})
  end
  vim.cmd "silent normal! u"
  M.put(items[i], last.key, last.count)
  last.index, last.tick = i, vim.b[buf].changedtick
  vim.api.nvim_echo({ { ("Yank %d/%d  "):format(i, #items) }, { M.label(items[i]), "Comment" } }, false, {})
end

--- Makes `entry` the current clipboard / unnamed register (what the next `p` pastes) and the top of the list
---@param entry HistoryYank
function M.select(entry)
  local reg = vim.o.clipboard:find "unnamedplus" and "+" or vim.o.clipboard:find "unnamed" and "*" or '"'
  vim.fn.setreg(reg, entry.lines, entry.type)
  M.add { lines = entry.lines, type = entry.type, time = os.time(), ft = entry.ft }
end

return M
