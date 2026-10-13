-- ── Test destination ─────────────────────────────────────────────────────────
-- The test actions do not replace the function: they APPEND to the end of the test file. The target the
-- pipeline sees is the LAST LINE of that file (or its single empty line if it is new): so one line is sent instead of
-- the whole file and the model returns only what is new (`merge` joins it). The code under test becomes the `subject`.
local convention = require "agent.tests.convention"

local M = {}

---@param subject AgentTarget the code under test
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
  -- the directory of a new file (test/, tests/...) is created on save, not before: rejecting leaves no folders behind
  if not info.exists then
    -- an empty file gives an LSP syntax error that would cover the proposal: no diagnostics until saved
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

--- The model returns only the NEW code: it goes after the last line (or is the whole file if it was empty)
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

--- Reason to stop if the target is a test file or does not deserve tests (before spending anything)
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
