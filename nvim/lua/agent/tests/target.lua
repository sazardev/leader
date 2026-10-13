-- ── Destino de las pruebas ───────────────────────────────────────────────────
-- Las acciones de pruebas no reemplazan la función: AÑADEN al final del archivo de pruebas. El objetivo que ve el
-- pipeline es la ÚLTIMA LÍNEA de ese archivo (o su única línea vacía si es nuevo): así se envía una línea en vez de
-- todo el archivo y el modelo solo devuelve lo nuevo (`merge` lo une). El código bajo prueba pasa a ser el `subject`.
local convention = require "agent.tests.convention"

local M = {}

---@param subject AgentTarget el código bajo prueba
---@return AgentTarget?, string? why
function M.retarget(subject)
  local abs = vim.api.nvim_buf_get_name(subject.buf)
  local info, why = convention.locate(abs, subject.lang)
  if not info then
    return nil, why
  end
  subject.tests = info

  local buf = info.inline and subject.buf or vim.fn.bufadd(info.path)
  if not vim.api.nvim_buf_is_loaded(buf) then
    vim.fn.bufload(buf)
  end
  if not info.exists and vim.bo[buf].filetype == "" then
    vim.bo[buf].filetype = subject.lang
  end
  -- el directorio de un archivo nuevo (test/, tests/...) se crea al guardar, no antes: rechazar no deja carpetas
  if not info.exists then
    -- un archivo vacío da un error de sintaxis del LSP que taparía la propuesta: sin diagnósticos hasta guardar
    vim.diagnostic.enable(false, { bufnr = buf })
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = buf,
      once = true,
      callback = function()
        vim.diagnostic.enable(true, { bufnr = buf })
      end,
    })
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = buf,
      once = true,
      callback = function()
        vim.fn.mkdir(vim.fs.dirname(info.path), "p")
      end,
    })
  end

  local n = vim.api.nvim_buf_line_count(buf)
  return {
    buf = buf,
    path = vim.fn.fnamemodify(info.path, ":."),
    lang = subject.lang,
    kind = "test-file-end",
    first = n,
    last = n,
    lines = vim.api.nvim_buf_get_lines(buf, n - 1, n, false),
    tests = info,
  }
end

--- El modelo devuelve solo el código NUEVO: va detrás de la última línea (o es el archivo entero si estaba vacío)
---@param code string[]
---@param target AgentTarget
---@return string[]
function M.merge(code, target)
  if #code == 0 then
    return target.lines
  end
  if not table.concat(target.lines):match "%S" then
    return code
  end
  local out = vim.list_slice(target.lines)
  out[#out + 1] = ""
  return vim.list_extend(out, code)
end

--- Motivo para no seguir si el objetivo es un archivo de pruebas o no merece pruebas (antes de gastar nada)
---@param subject AgentTarget
---@return string?
function M.check(subject)
  if convention.is_test_file(vim.api.nvim_buf_get_name(subject.buf)) then
    return "this is already a test file (<leader>aTf fixes a failing test)"
  end
  if subject.kind == "function" then
    local code = 0
    for _, l in ipairs(subject.lines) do
      if l:match "%S" then
        code = code + 1
      end
    end
    if code < 4 then
      return "too small to be worth a test (select it in visual mode to force)"
    end
  end
end

return M
