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
    local from = 1 -- walk the buffer once: cutting the front off per line is quadratic on a big chunk
    while true do
      local nl = pending:find("\n", from, true)
      if not nl then
        break
      end
      local line = pending:sub(from, nl - 1)
      from = nl + 1
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
    if from > 1 then
      pending = pending:sub(from)
    end
    return #out > 0 and table.concat(out) or nil
  end
end

return M
