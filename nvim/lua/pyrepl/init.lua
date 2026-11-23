-- ── Python REPL workspace (<leader>pC) ────────────────────────────────────────
-- Una sesión IPython por nombre, su propio archivo de celdas en
-- stdpath("state")/python-repl, salida segmentada y el modelo local en el mismo
-- sitio (explicar, generar, chat y FIM). Un folder, una responsabilidad:
-- cells/output/cmd son puros, files guarda, model habla con el agente, ui muestra.
local M = {}

local cells = require "pyrepl.cells"
local output = require "pyrepl.output"
local files = require "pyrepl.files"
local repl_cmd = require "pyrepl.cmd"
local model = require "pyrepl.model"
local repl_ui = require "pyrepl.ui"
local terminal = require "utils.terminal"
local log = require "utils.log"

local current

local function config()
  local ok, settings = pcall(require, "core.settings")
  return ok and settings.python and settings.python.repl or {}
end

local function root()
  return require("utils.python").root()
end

--- La sesión activa; la primera vez toma la más reciente o crea "default".
---@return string
function M.session()
  if not current then
    current = files.last() or config().session or "default"
    files.ensure(current, root())
  end
  return current
end

local function slice(lines, first, last)
  local out = {}
  for i = first, last do
    out[#out + 1] = lines[i]
  end
  return out
end

---@return string
local function command()
  local cmd = repl_cmd.repl(root())
  if not cmd then
    log.warn "Python REPL: IPython is not installed (uv add --dev ipython)"
  end
  return cmd
end

--- Nueva sesión (o cambio entre las existentes) desde el picker.
function M.new_session()
  files.pick(function(name)
    if name == "__new__" then
      vim.ui.input({ prompt = "Python REPL session: " }, function(answer)
        if answer and vim.trim(answer) ~= "" then
          M.open_session(answer)
        end
      end)
    else
      M.open_session(name)
    end
  end)
end

---@param name string
function M.open_session(name)
  current = name
  local path = files.ensure(name, root())
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  log.info("Python REPL: session " .. name)
end

--- Abre/crea la sesión por defecto y su archivo de celdas (para el menú).
function M.workspace()
  M.open_session(M.session())
end

--- Texto de la celda bajo el cursor, o de la selección visual.
---@return string
function M.current_cell_text()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local first, last
  if vim.fn.mode():match "[vV\22]" then
    first, last = vim.fn.getpos("v")[2], vim.fn.getpos(".")[2]
    if first > last then
      first, last = last, first
    end
    vim.cmd "normal! \27"
  else
    local cell = cells.at(lines, vim.fn.line ".")
    if not cell then
      return ""
    end
    first, last = cell.first, cell.last
  end
  return table.concat(slice(lines, first, last), "\n")
end

--- Envía la celda bajo el cursor (o la selección) a la terminal de la sesión.
function M.send_cell()
  local text = vim.trim(M.current_cell_text())
  if text == "" then
    return log.warn "Python REPL: no cell under the cursor"
  end
  local cmd = command()
  if not cmd then
    return
  end
  local name = M.session()
  terminal.send_text(repl_cmd.term_name(name), cmd, root(), text, true)
  log.info(("Python REPL: sent cell to %s"):format(name))
end

--- Inserta marcadores `# %%` en los bloques de nivel superior del archivo.
function M.split_cells()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local separated = cells.split(lines)
  if vim.deep_equal(separated, lines) then
    return log.info "Python REPL: the code is already split into cells"
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, separated)
  log.info "Python REPL: split code into cells"
end

--- Las últimas líneas de la terminal de la sesión (o de la última terminal).
---@return string
function M.output_text()
  local name = M.session()
  local limit = config().output_lines or 120
  local term = terminal.named(repl_cmd.term_name(name))
  if term and term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
    local count = vim.api.nvim_buf_line_count(term.bufnr)
    local lines = vim.api.nvim_buf_get_lines(term.bufnr, math.max(0, count - limit), count, false)
    return output.strip(table.concat(lines, "\n"))
  end
  return output.strip(require("agent.errors.source").terminal(limit) or "")
end

--- Muestra la salida separada por prompts y la guarda en la carpeta de la sesión.
function M.segment_output()
  local text = M.output_text()
  if vim.trim(text) == "" then
    return log.warn "Python REPL: there is no output yet"
  end
  local blocks = output.parse(text)
  local rendered = output.text(blocks)
  files.save_output(M.session(), rendered)
  repl_ui.float("REPL output · " .. M.session(), rendered, "text")
end

--- Explica la salida con el modelo local (tier light).
function M.explain_output()
  local text = M.output_text()
  if vim.trim(text) == "" then
    return log.warn "Python REPL: there is no output yet"
  end
  model.explain(text, function(ok, answer)
    vim.schedule(function()
      if not ok then
        return log.warn("Python REPL: " .. tostring(answer))
      end
      repl_ui.float("REPL explain · " .. model.label(), answer, "markdown")
    end)
  end)
end

--- Pide código al modelo local y lo ejecuta directamente en la sesión.
function M.generate()
  vim.ui.input({ prompt = "Ask the local model (Python code): " }, function(instruction)
    if not instruction or vim.trim(instruction) == "" then
      return
    end
    local context = M.current_cell_text()
    model.generate(instruction, context, function(ok, answer)
      vim.schedule(function()
        if not ok then
          return log.warn("Python REPL: " .. tostring(answer))
        end
        local code = model.clean_code(answer)
        if vim.trim(code) == "" then
          return log.warn "Python REPL: the model returned no code"
        end
        local cmd = command()
        if not cmd then
          return
        end
        local name = M.session()
        terminal.send_text(repl_cmd.term_name(name), cmd, root(), code, true)
        repl_ui.float("REPL generated · " .. model.label(), code, "python")
      end)
    end)
  end)
end

--- Abre el chat con la celda actual y la salida de la sesión como contexto.
function M.chat()
  local prefill = "Sobre esta sesión de IPython:\n\n"
  local cell = vim.trim(M.current_cell_text())
  if cell ~= "" then
    prefill = prefill .. "<cell>\n" .. cell .. "\n</cell>\n\n"
  end
  local text = M.output_text()
  if vim.trim(text) ~= "" then
    prefill = prefill .. "<repl_output>\n" .. text .. "\n</repl_output>\n\n"
  end
  prefill = prefill .. "Pregunta: "
  model.chat(prefill)
end

--- Alterna la finalización FIM local (la usa cualquier buffer, incluidas las celdas).
function M.fim()
  log.info("Python REPL: local completion " .. (model.fim() and "on" or "off"))
end

return M
