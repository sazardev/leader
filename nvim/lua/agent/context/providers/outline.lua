-- File outline: header (imports) + first line of each declaration. Cheap (no
-- LSP) and tells the model what else exists around it so it does not invent names.
local scopes = require "agent.context.scopes"

local MAX_ENTRIES = 40
local MAX_HEADER = 25

return {
  cap = 2500,
  stability = 2,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  ---@param ctx { names: string[] }?
  collect = function(target, done, ctx)
    local with_types = ctx and vim.tbl_contains(ctx.names, "types")
    local all = scopes.declarations(target.buf)
    -- types already go with their fields in <types>; the header (imports) is measured against ALL the declarations
    local decls = vim.tbl_filter(function(d)
      return not (with_types and d.kind == "class")
    end, all)
    if #all == 0 then
      return done(nil)
    end

    local out = {}
    -- header: what comes before the first declaration (package/imports/use...)
    local header_end = math.min(all[1].row, MAX_HEADER)
    if header_end > 0 and target.first - 1 >= header_end then
      local header = vim.tbl_filter(function(l)
        return l:match "%S"
      end, vim.api.nvim_buf_get_lines(target.buf, 0, header_end, false))
      if #header > 0 then
        out[#out + 1] = table.concat(header, "\n")
        out[#out + 1] = ""
      end
    end

    local count = 0
    for _, d in ipairs(decls) do
      local inside = d.row + 1 >= target.first and d.row + 1 <= target.last
      if not inside and count < MAX_ENTRIES then
        local line = vim.api.nvim_buf_get_lines(target.buf, d.row, d.row + 1, false)[1] or ""
        out[#out + 1] = ("L%d %s"):format(d.row + 1, vim.trim(line):sub(1, 110))
        count = count + 1
      end
    end
    done(table.concat(out, "\n"))
  end,
}
