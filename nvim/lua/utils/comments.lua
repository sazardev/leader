-- ── Foldable long comments ───────────────────────────────────────────────────
-- Uses treesitter to detect multi-line comments (a `/* */` block or several consecutive
-- `//` lines that stand alone on their line) and exposes them as nvim-ufo folds
-- (kind "longcomment", see plugins/editing/ufo.lua). The <leader>C menu folds/unfolds them and
-- saves the preference (it persists when opening other files and across restarts).
-- Without a parser there are no comments to detect: the menu warns and does nothing.
local M = {}

--- `kind` under which the long-comment folds are registered in ufo (unique: the treesitter
--- provider uses the node name, e.g. "comment", and would also close short comments)
M.KIND = "longcomment"

-- Comment node names by grammar; only the one that exists in the language is valid
local NODE_TYPES = { "comment", "line_comment", "block_comment", "multiline_comment", "documentation_comment" }

---@type table<string, vim.treesitter.Query|false>
local queries = {}

---@param lang string
---@return vim.treesitter.Query?
local function comment_query(lang)
  if queries[lang] == nil then
    local valid = {}
    for _, name in ipairs(NODE_TYPES) do
      if pcall(vim.treesitter.query.parse, lang, "(" .. name .. ") @c") then
        valid[#valid + 1] = "(" .. name .. ")"
      end
    end
    queries[lang] = #valid > 0 and vim.treesitter.query.parse(lang, "[" .. table.concat(valid, " ") .. "] @c") or false
  end
  return queries[lang] or nil
end

---@class CommentRange
---@field first integer row (0-based) where it starts
---@field last integer row (0-based, inclusive) where it ends

--- Comments of `min_lines` lines or more, sorted. Comments at the end of a
--- code line don't count; consecutive `//` lines are merged into one.
---@param buf integer
---@return CommentRange[]
function M.ranges(buf)
  local min_lines = require("core.settings").comments.min_lines
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if not (ok and parser) then
    return {}
  end
  parser:parse()

  local nodes = {}
  parser:for_each_tree(function(tree, ltree)
    local query = comment_query(ltree:lang())
    if not query then
      return
    end
    for _, node in query:iter_captures(tree:root(), buf) do
      local sr, sc, er, ec = node:range()
      if ec == 0 and er > sr then
        er = er - 1 -- an end at column 0 includes the line break
      end
      -- only comments that start alone on their line
      local before = vim.api.nvim_buf_get_text(buf, sr, 0, sr, sc, {})[1] or ""
      if not before:find "%S" then
        nodes[#nodes + 1] = { first = sr, last = er }
      end
    end
  end)
  table.sort(nodes, function(a, b)
    return a.first < b.first
  end)

  local merged = {}
  for _, n in ipairs(nodes) do
    local prev = merged[#merged]
    -- consecutive comment lines = a single comment (a `/* */` block is never merged)
    if prev and prev.line_run and n.first == n.last and n.first == prev.last + 1 then
      prev.last = n.last
    else
      merged[#merged + 1] = { first = n.first, last = n.last, line_run = n.first == n.last }
    end
  end

  local result = {}
  for _, c in ipairs(merged) do
    if c.last - c.first + 1 >= min_lines then
      result[#result + 1] = { first = c.first, last = c.last }
    end
  end
  return result
end

--- Is the comment right now a closed fold of exactly its size?
---@param c CommentRange
---@return boolean
local function is_closed(c)
  local lnum = c.first + 1
  return vim.fn.foldclosed(lnum) == lnum and vim.fn.foldclosedend(lnum) == c.last + 1
end

---@param c CommentRange
local function close(c)
  if vim.fn.foldclosed(c.first + 1) == -1 then
    pcall(vim.cmd, c.first + 1 .. "foldclose")
  end
end

---@param c CommentRange
local function open(c)
  if is_closed(c) then
    pcall(vim.cmd, c.first + 1 .. "foldopen")
  end
end

-- ── Persistent preference ────────────────────────────────────────────────────
-- "Collapsed comments" is global and saved in stdpath("state")/comments.json (like the ones in
-- utils/diagblocks.lua): `<leader>Cc` turns it on, `<leader>Ce` turns it off, and it applies to the files
-- you open afterwards and to future sessions. `settings.comments.auto_collapse` only gives the
-- initial value, until you choose something.
local PREFS_PATH = vim.fn.stdpath "state" .. "/comments.json"

---@type { collapsed: boolean }?
local prefs

---@return { collapsed: boolean }
local function get_prefs()
  if prefs then
    return prefs
  end
  prefs = { collapsed = require("core.settings").comments.auto_collapse }
  local f = io.open(PREFS_PATH, "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read "*a")
    f:close()
    if ok and type(data) == "table" and type(data.collapsed) == "boolean" then
      prefs.collapsed = data.collapsed
    end
  end
  return prefs
end

---@param collapsed boolean
local function set_collapsed(collapsed)
  get_prefs().collapsed = collapsed
  vim.fn.mkdir(vim.fn.fnamemodify(PREFS_PATH, ":h"), "p")
  local f = io.open(PREFS_PATH, "w")
  if f then
    f:write(vim.json.encode(prefs))
    f:close()
  end
end

---@return boolean
function M.collapsed()
  return get_prefs().collapsed
end

--- Kinds that ufo closes by itself the first time it shows a buffer: with the preference on,
--- new files open with the long comments already folded
---@return string[]
function M.close_kinds()
  return M.collapsed() and { M.KIND } or {}
end

--- ufo reads this list live (the one in its config): the kind is added or removed without restarting anything
local function sync_ufo()
  local ok, config = pcall(require, "ufo.config")
  if not ok then
    return
  end
  local kinds = config.close_fold_kinds_for_ft.default or {}
  config.close_fold_kinds_for_ft.default = kinds
  for i = #kinds, 1, -1 do
    if kinds[i] == M.KIND then
      table.remove(kinds, i)
    end
  end
  if M.collapsed() then
    kinds[#kinds + 1] = M.KIND
  end
end

-- ── Actions ───────────────────────────────────────────────────────────────────

--- Fold or unfold all long comments of the current window's buffer
---@param collapse boolean
---@return integer how many long comments there are
local function apply_here(collapse)
  local ranges = M.ranges(vim.api.nvim_get_current_buf())
  if #ranges > 0 then
    vim.wo.foldenable = true
  end
  for _, c in ipairs(ranges) do
    if collapse then
      close(c)
    else
      open(c)
    end
  end
  return #ranges
end

--- Fold INSTANTLY, synchronously and before the first redraw, a just-shown buffer.
--- ufo's provider is asynchronous (the file would look open for a few tens of ms and then
--- "jump"): here the long-comment folds are created and closed on the spot; when
--- ufo finishes, it redoes all the folds and closes them again by kind unnoticeably.
--- It only acts if the buffer has no folds yet (if it already has them, ufo already worked: `apply_here` aligns it).
---@param buf integer
---@return integer how many long comments it folds
local function fold_now(buf)
  if vim.wo.foldmethod ~= "manual" then
    return 0
  end
  local ranges = M.ranges(buf)
  for _, c in ipairs(ranges) do
    if vim.fn.foldlevel(c.first + 1) > 0 then
      return 0
    end
  end
  if #ranges > 0 then
    vim.wo.foldenable = true
  end
  for _, c in ipairs(ranges) do
    -- bottom-to-top isn't needed: comments don't overlap each other
    pcall(vim.cmd, ("%d,%dfold"):format(c.first + 1, c.last + 1))
    close(c)
  end
  return #ranges
end

--- Apply the preference to what is already open in this tab (new files take it from ufo)
---@param collapse boolean
---@return integer
local function apply_visible(collapse)
  local total = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
      total = total + vim.api.nvim_win_call(win, function()
        return apply_here(collapse)
      end)
    end
  end
  return total
end

--- Fold all long comments and keep them folded (saved preference)
function M.collapse()
  set_collapsed(true)
  sync_ufo()
  local n = apply_visible(true)
  vim.notify(
    n > 0 and ("Collapsed %d comments — they stay collapsed (<leader>Ce to undo)"):format(n)
      or ("No comments of %d+ lines here; they will be collapsed in files that have them"):format(
        require("core.settings").comments.min_lines
      ),
    vim.log.levels.INFO
  )
end

--- Unfold all long comments and stop folding them automatically
function M.expand()
  set_collapsed(false)
  sync_ufo()
  apply_visible(false)
  vim.notify("Comments expanded — they will open expanded", vim.log.levels.INFO)
end

--- Fold/unfold the long comment under the cursor (only there: doesn't change the preference)
function M.toggle()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  for _, c in ipairs(M.ranges(vim.api.nvim_get_current_buf())) do
    if c.first <= row and row <= c.last then
      vim.wo.foldenable = true
      if is_closed(c) then
        return open(c)
      end
      return close(c)
    end
  end
  vim.notify("No long comment under the cursor", vim.log.levels.INFO)
end

--- Register the preference in ufo and apply it to the buffers that already existed when it was turned on
--- (new ones are closed by ufo itself): when shown, a buffer whose state doesn't match gets aligned
function M.setup()
  sync_ufo()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("CommentFolds", { clear = true }),
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" then
        return
      end
      local want = M.collapsed()
      if vim.b[ev.buf].comments_collapsed == want then
        return
      end
      -- when opening a file it is folded right away, without waiting for ufo (which is asynchronous)
      if want and vim.api.nvim_get_current_buf() == ev.buf and fold_now(ev.buf) > 0 then
        vim.b[ev.buf].comments_collapsed = true
        return
      end
      -- otherwise (buffer already with folds, or unfolding): wait for ufo to have them
      vim.defer_fn(function()
        if not (vim.api.nvim_buf_is_valid(ev.buf) and vim.api.nvim_get_current_buf() == ev.buf) then
          return
        end
        if want == M.collapsed() and apply_here(want) > 0 then
          vim.b[ev.buf].comments_collapsed = want
        end
      end, 300)
    end,
  })
end

return M
