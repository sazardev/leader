-- ── JSON lines reader (NDJSON) ───────────────────────────────────────────────
-- CLIs emit one JSON object per line, but stdout chunks arrive cut at arbitrary
-- points. It buffers the incomplete part and delivers only whole, already-decoded lines.
local M = {}

---@param handler fun(obj: table): string? returns new text (if the event carries it)
---@return fun(chunk: string): string?
function M.new(handler)
  local pending = ""
  return function(chunk)
    pending = pending .. chunk
    local out = {}
    while true do
      local nl = pending:find("\n", 1, true)
      if not nl then
        break
      end
      local line = pending:sub(1, nl - 1)
      pending = pending:sub(nl + 1)
      if line:match "%S" then
        local ok, obj = pcall(vim.json.decode, line)
        if ok and type(obj) == "table" then
          local piece = handler(obj)
          if piece then
            out[#out + 1] = piece
          end
        end
      end
    end
    return #out > 0 and table.concat(out) or nil
  end
end

return M
