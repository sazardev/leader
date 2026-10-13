-- ── Inline preview of a replacement ──────────────────────────────────────────
-- What is deleted is tinted red in place; what is added appears in green right below,
-- as virtual lines (they do not exist in the buffer until you accept). Only the
-- hunks that change are painted, not the whole block.
local diff = require "agent.output.diff"

require("agent.ui.highlights").ensure()

local M = {}

local NS = vim.api.nvim_create_namespace "agent.preview"

--- Virtual lines do not expand tabs: it is done by hand, and padded up to the edge
---@param buf integer
---@param line string
---@param width integer
---@return string
local function virtual_line(buf, line, width)
  local text = line:gsub("\t", (" "):rep(vim.bo[buf].tabstop))
  local pad = width - vim.fn.strdisplaywidth(text)
  return pad > 0 and text .. (" "):rep(pad) or text
end

---@param buf integer
---@param first integer 1-based, start of the old block
---@param old string[]
---@param new string[]
---@param hint string|fun(hunks: integer): string text to the right of the first line
---@return integer[] ids  extmarks created (to clean up)
---@return integer hunks  how many hunks change
function M.render(buf, first, old, new, hint)
  local ids = {}
  local width = vim.o.columns
  local hunks = diff.hunks(old, new)

  local function mark(row, opts)
    opts.strict = false
    ids[#ids + 1] = vim.api.nvim_buf_set_extmark(buf, NS, row, 0, opts)
  end

  for _, h in ipairs(hunks) do
    -- row (0-based) of old line `i` (1-based within the block)
    local function row_of(i)
      return first - 2 + i
    end

    for i = h.a_start, h.a_start + h.a_count - 1 do
      mark(row_of(i), { line_hl_group = "AgentDiffDelete" })
    end

    if h.b_count > 0 then
      local virt = {}
      for j = h.b_start, h.b_start + h.b_count - 1 do
        virt[#virt + 1] = { { virtual_line(buf, new[j], width), "AgentDiffAdd" } }
      end
      if h.a_count > 0 then
        mark(row_of(h.a_start + h.a_count - 1), { virt_lines = virt })
      elseif h.a_start == 0 then
        mark(first - 1, { virt_lines = virt, virt_lines_above = true })
      else
        mark(row_of(h.a_start), { virt_lines = virt })
      end
    end
  end

  local label = type(hint) == "function" and hint(#hunks) or hint
  -- the hint goes on its own virtual line above: on the right it would cover code
  mark(first - 1, { virt_lines = { { { " " .. label, "AgentHint" } } }, virt_lines_above = true })
  return ids, #hunks
end

---@param buf integer
---@param ids integer[]
function M.clear(buf, ids)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for _, id in ipairs(ids) do
    pcall(vim.api.nvim_buf_del_extmark, buf, NS, id)
  end
end

return M
