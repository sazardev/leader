-- ── The customize step as a full-screen marketplace ──────────────────────────
-- STACK.md and DESIGN.md add-ons (and the package manager of a pnpm stack) by group, one-of groups as radios. The one under
-- the cursor is read on the right (what it is, what it writes in the document), the strip says what the choice sets, and
-- `p` shows exactly the text the document would gain. Same keys as the SPEC.md modules' marketplace (utils/market.lua):
-- Space picks, ⏎ goes on (the step's "Next"), Esc goes back.
local market = require "utils.market"
local modal = require "utils.modal"
local presets = require "agent.kit.presets"

local M = {}

---@class AddonMarket: Market
---@field list KitChoice[]
---@field checked table<string, boolean>
---@field exclusive table<string, boolean>
---@field doc string

---@param list KitChoice[]
---@return table<string, boolean>
local function exclusive_groups(list)
  local out = {}
  for _, c in ipairs(list) do
    out[c.group] = c.group == "Package manager" or presets.exclusive(c.group)
  end
  return out
end

--- The Stack rows an add-on sets: the first cell of every table row of its `## Stack` section (what a merge replaces)
---@param body string
---@return string[]
function M.rows_of(body)
  local section = body:match "## Stack%s*\n(.-)\n## " or body:match "## Stack%s*\n(.*)" or ""
  local out = {}
  for line in section:gmatch "[^\n]+" do
    local key = line:match "^|%s*([^|]-)%s*|"
    if key and key ~= "" and not key:match "^[-:%s]+$" then
      out[#out + 1] = key
    end
  end
  return out
end

--- The rows (pure): the title, then each group with its choices; narrowed by the filter
---@param st { list: KitChoice[], checked: table<string, boolean>, exclusive: table<string, boolean>, filter: string, doc: string, focus: table<string, boolean>? }
---@return table[]
function M.rows(st)
  local needle = vim.trim(st.filter or ""):lower()
  local rows, group = { { title = st.doc .. " ADD-ONS" }, { spacer = true } }, nil
  for _, c in ipairs(st.list) do
    local hay = (c.name .. " " .. c.group .. " " .. (c.addon and c.addon.desc or "")):lower()
    if needle == "" or hay:find(needle, 1, true) then
      if c.group ~= group then
        if group then
          rows[#rows + 1] = { spacer = true }
        end
        group = c.group
        rows[#rows + 1] = { group = c.group, one = st.exclusive[c.group], focus = st.focus and st.focus[c.group] }
      end
      rows[#rows + 1] =
        { choice = c, on = st.checked[c.key] == true, one = st.exclusive[c.group], focus = st.focus and st.focus[c.group] }
    end
  end
  return rows
end

---@param row table
---@return MarketLine
function M.list_line(row)
  if row.title then
    return { { "  " .. row.title, modal.hl.key } }
  elseif row.spacer then
    return { { "" } }
  elseif row.group then
    return {
      { (row.collapsed and "▸ " or "  ") .. row.group:upper(), row.focus and modal.hl.key or modal.hl.muted },
      { row.one and "  one of" or "", modal.hl.muted },
      { row.focus and "  ★" or "", modal.hl.mark },
    }
  end
  local mark = row.one and (row.on and " ● " or " ○ ") or (row.on and " ■ " or " □ ")
  return {
    { mark, row.on and modal.hl.mark or modal.hl.muted },
    { row.choice.name, row.on and modal.hl.file or modal.hl.muted },
  }
end

--- An add-on's text as the pane reads it: its sections, table rows as "Row: value", bullets wrapped
---@param body string
---@param width integer
---@return MarketLine[]
function M.body_lines(body, width)
  local lines, fenced = {}, false
  for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
    if line:match "^```" then
      fenced = not fenced
    elseif fenced then
      lines[#lines + 1] = { { "    " .. line, modal.hl.muted } }
    elseif line:match "^## " then
      lines[#lines + 1] = { { "" } }
      lines[#lines + 1] = { { "  " .. line:sub(4):upper(), modal.hl.key } }
    elseif line:match "^|" then
      local cells = vim.tbl_map(vim.trim, vim.split(line:sub(2, -2), "|", { plain = true }))
      if cells[1] and not cells[1]:match "^[-:%s]+$" then
        for i, row in ipairs(market.wrap((cells[1] .. ": " .. (cells[2] or "")):gsub("`", ""), width - 4)) do
          lines[#lines + 1] = { { (i == 1 and "  " or "    ") .. row, modal.hl.file } }
        end
      end
    elseif vim.trim(line) ~= "" then
      local bullet = line:match "^%s*[-*]%s+(.+)$"
      for i, row in ipairs(market.wrap((bullet or line):gsub("`", ""), width - 6)) do
        lines[#lines + 1] = { { "  " .. (bullet and (i == 1 and "· " or "  ") or "") .. row, modal.hl.muted } }
      end
    end
  end
  return lines
end

--- What the strip says: how many are picked, which, and the Stack rows they set
---@param st { list: KitChoice[], checked: table<string, boolean>, doc: string }
---@return MarketLine[]
function M.summary(st)
  local picked, rows = {}, {}
  for _, c in ipairs(st.list) do
    if st.checked[c.key] and (c.addon or c.pm) then
      picked[#picked + 1] = c.name
      for _, r in ipairs(c.addon and M.rows_of(c.addon.body) or {}) do
        if not vim.tbl_contains(rows, r) then
          rows[#rows + 1] = r
        end
      end
    end
  end
  local lines = { { { "  " .. st.doc .. " GETS", modal.hl.key } } }
  if #picked == 0 then
    lines[#lines + 1] = { { "  Nothing picked: the document stays as it is", modal.hl.muted } }
    return lines
  end
  local shown, width = {}, 0
  for i, name in ipairs(picked) do -- as many as fit on one line, then "+N more"
    width = width + vim.fn.strdisplaywidth(name) + 3
    if width > vim.o.columns - 16 and i < #picked then
      shown[#shown + 1] = ("+%d more"):format(#picked - i + 1)
      break
    end
    shown[#shown + 1] = name
  end
  lines[#lines + 1] = { { "  " .. table.concat(shown, " · "), modal.hl.file } }
  lines[#lines + 1] = {
    { ("  %d choice%s"):format(#picked, #picked == 1 and "" or "s") .. (#rows > 0 and (" · sets the rows " .. table.concat(rows, ", ")) or ""), modal.hl.muted },
  }
  return lines
end

--- Opens the step
---@param opts { title: string, doc: string?, focus: string[]?, why: string?, list: KitChoice[], checked: table<string, boolean>, base: string?, apply: (fun(text: string, list: KitChoice[], checked: table<string, boolean>): string)?, done: fun(checked: table<string, boolean>), back: fun()? }
---@return AddonMarket
function M.open(opts)
  local st = {
    list = opts.list,
    checked = vim.deepcopy(opts.checked or {}),
    exclusive = exclusive_groups(opts.list),
    doc = opts.doc or "STACK.md",
  }
  if opts.focus and #opts.focus > 0 then -- group labels → a set
    st.focus = {}
    for _, label in ipairs(opts.focus) do
      st.focus[label] = true
    end
  end

  ---@param m AddonMarket
  ---@param row table?
  local function toggle(m, row)
    local c = row and row.choice
    if not c then
      return
    end
    local on = not m.checked[c.key]
    m.checked[c.key] = on or nil
    if on and m.exclusive[c.group] then -- one of: the others in the group go off
      for _, other in ipairs(m.list) do
        if other.group == c.group and other.key ~= c.key then
          m.checked[other.key] = nil
        end
      end
    end
    market.refresh(m)
  end
  local function leave(m, how)
    market.close(m)
    local checked = vim.deepcopy(m.checked)
    vim.schedule(function()
      if how == "next" then
        opts.done(checked)
      elseif opts.back then
        opts.back()
      end
    end)
  end

  local result
  if opts.base and opts.apply then
    result = function(m)
      local lines = { { { "  WHAT " .. m.doc .. " GETS", modal.hl.key } }, { { "" } } }
      local new = opts.apply(opts.base, m.list, m.checked)
      local added = require("agent.kit.specmodules").added_lines(opts.base, new)
      if #added == 0 then
        lines[#lines + 1] = { { "  Nothing changes (Esc back)", modal.hl.muted } }
      end
      for _, l in ipairs(added) do
        lines[#lines + 1] = { { "  " .. l, l:match "^#" and modal.hl.file or modal.hl.muted } }
      end
      return lines
    end
  end

  return market.new({
    title = opts.title,
    summary_rows = 6,
    rows = M.rows,
    selectable = function(row)
      return row.choice ~= nil
    end,
    list_line = M.list_line,
    pane = function(_, row, width)
      local c = row and row.choice
      if not c then
        return { { { "" } } }, {}
      end
      local lines = { { { "  " .. c.name:upper(), modal.hl.key } } }
      local desc = c.addon and c.addon.desc or "Rewrites every command, the lockfile and the Stack row to use it"
      for _, r in ipairs(market.wrap(desc, width - 4)) do
        lines[#lines + 1] = { { "  " .. r, modal.hl.muted } }
      end
      lines[#lines + 1] = {
        { "  " .. c.group .. (row.one and " · pick one: choosing it replaces the others" or " · any number"), modal.hl.muted },
      }
      if row.focus then
        lines[#lines + 1] = { { "  ★ " .. (opts.why and ("goes with " .. opts.why) or "suggested"), modal.hl.mark } }
      end
      if c.addon then
        vim.list_extend(lines, M.body_lines(c.addon.body, width))
      end
      return lines, {}
    end,
    result = result,
    summary = function(m)
      return M.summary(m)
    end,
    hints = function(_, mode)
      if mode == "result" then
        return { { "Esc", "back" }, { "⏎", "next" } }
      elseif mode == "pane" then
        return { { "Esc", "back to the list" }, { "?", "keys" } }
      end
      local keys = { { "Space", "pick" }, { "⏎", "next" }, { "/", "filter" } }
      if result then
        keys[#keys + 1] = { "p", "what it writes" }
      end
      keys[#keys + 1] = { "Esc", opts.back and "back" or "close" }
      keys[#keys + 1] = { "?", "keys" }
      return keys
    end,
    help = {
      { "Space x", "pick (in a one-of group the others go off; pick it again to have none)" },
      { "⏎", "next step, with what is picked" },
      { "Esc q", opts.back and "back one step, keeping what you picked" or "close" },
      { "l", "read the whole add-on (scroll it; Esc goes back)" },
    },
    initial = function(m) -- the cursor starts on the first group that was suggested
      for i, r in ipairs(m.rows) do
        if r.choice and r.focus then
          return i
        end
      end
    end,
    cancel = function(m)
      leave(m, "back")
    end,
    keys = {
      list = { { "<Space>", toggle, "Pick" }, { "x", toggle, "Pick" } },
      all = {
        {
          "<CR>",
          function(m, _)
            leave(m, "next")
          end,
          "Next",
        },
      },
    },
  }, st)
end

return M
