-- Corre una prueba (comando de convention.command) y devuelve solo lo útil de su salida. Sin modelo: es el trabajo
-- previo de `fix`, para no pagar tokens por arreglar una prueba que ya pasa.
local M = {}

local TIMEOUT_MS = 90000
local OUTPUT_MAX = 2500

--- Quita colores y el ruido de lo que pasa, y recorta
---@param raw string
---@return string
function M.clean(raw)
  local lines = {}
  for _, l in ipairs(vim.split((raw:gsub("\27%[[%d;]*m", "")), "\n", { plain = true })) do
    local noise = l:match "^%s*$"
      or l:match "^=== RUN"
      or l:match "^%-%-%- PASS"
      or l:match "^PASS$"
      or l:match "^ok%s"
      or l:match "^%s*%.+%s*%[?%s*%d*%%?%]?%s*$"
    if not noise then
      lines[#lines + 1] = l
    end
  end
  local text = table.concat(lines, "\n")
  return #text > OUTPUT_MAX and (text:sub(1, OUTPUT_MAX) .. "\n[… cut]") or text
end

---@param run AgentTestRun
---@param cb fun(ok: boolean, output: string, err: string?)  ok = las pruebas PASAN
function M.exec(run, cb)
  if vim.fn.executable(run.cmd[1]) ~= 1 then
    return cb(false, "", ("`%s` is not installed"):format(run.cmd[1]))
  end
  vim.system(run.cmd, { cwd = run.cwd, text = true, timeout = TIMEOUT_MS }, function(res)
    vim.schedule(function()
      local timed_out = res.signal == 15 or res.code == 124
      if timed_out then
        return cb(false, "", ("timed out (%ds)"):format(TIMEOUT_MS / 1000))
      end
      cb(res.code == 0, M.clean((res.stdout or "") .. "\n" .. (res.stderr or "")))
    end)
  end)
end

return M
