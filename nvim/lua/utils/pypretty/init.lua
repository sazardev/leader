-- ── Pretty Python output ────────────────────────────────────────────────────
-- <leader>pr runs the file through `runner.py` (next to this module): the same `python file.py` (argv, sys.path,
-- __main__, exit code) with a Jupyter-style view of numpy arrays and pandas frames, colored values and a clean
-- traceback. Pure: it only builds a command string.
local M = {}

--- The runner, found next to this module (like agent/kit/build/use/drivers/web_runner.cjs)
---@return string
function M.runner()
  return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/runner.py"
end

--- `python runner.py [--light] [--locals] 'file'`: the project's interpreter, unchanged, plus the runner.
--- The flags go after the runner: `uv run python --light ...` would give `--light` to the interpreter.
---@param python string the project's interpreter ("uv run python", a quoted .venv python, "python3")
---@param file string absolute path of the script
---@param opts { light: boolean?, locals: boolean?, clear: boolean?, plots: boolean? }? -- theme, traceback, pane, plots
---@return string
function M.command(python, file, opts)
  local parts = { python, vim.fn.shellescape(M.runner()) }
  if opts and opts.light then
    parts[#parts + 1] = "--light"
  end
  if opts and opts.locals then
    parts[#parts + 1] = "--locals"
  end
  if opts and opts.clear == false then
    parts[#parts + 1] = "--no-clear"
  end
  if opts and opts.plots == false then
    parts[#parts + 1] = "--no-plots"
  end
  parts[#parts + 1] = vim.fn.shellescape(file)
  return table.concat(parts, " ")
end

return M
