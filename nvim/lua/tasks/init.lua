-- ── Project tasks (<leader>R): the targets of the project's Makefile, one picker ─────────────────────────────────────
-- It works with a Makefile and ONLY with a Makefile (`make.lua` lists its targets); without one every action says so, and
-- `<leader>Rc` creates one from a preset (`create.lua`, `presets/`). Nothing here calls a model and nothing stays running:
-- make is asked only when the picker opens (the answer is cached until the Makefile or its `*.mk` change). Targets run in the
-- integrated terminal (`exec.lua`).
local log = require "utils.log"
local make = require "tasks.make"
local store = require "tasks.store"
local util = require "tasks.util"

local M = {}

--- What make answered: Makefile path → { stamp, tasks }, valid while the stamp (mtime + size of the files) is the same
M.cache = {}

--- The directory the search starts from: the current file's, else the cwd
---@return string
function M.dir()
  local name = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype == "" and name ~= "" and vim.fn.filereadable(name) == 1 then
    return vim.fs.dirname(name)
  end
  return vim.fn.getcwd()
end

--- The Makefile at or above `dir`. Without one it says so (and where to get one) and returns nil
---@param dir string
---@return string?
function M.need(dir)
  local file = make.detect(dir, util.stop(dir))
  if not file then
    log.info(("Tasks: no Makefile above %s (<leader>Rc creates one from a preset)"):format(vim.fn.fnamemodify(dir, ":~")))
  end
  return file
end

--- The default goal first, then the Makefile's own order
---@param tasks Task[]
---@return Task[]
function M.sort(tasks)
  local index = {}
  for i, t in ipairs(tasks) do
    index[t] = i
  end
  table.sort(tasks, function(a, b)
    if (a.default or false) ~= (b.default or false) then
      return a.default or false
    end
    return index[a] < index[b]
  end)
  return tasks
end

--- The targets of a Makefile (cached)
---@param file string
---@param opts { force: boolean? }?
---@param cb fun(tasks: Task[])
function M.collect(file, opts, cb)
  local stamp = make.stamp(file)
  local hit = M.cache[file]
  if hit and hit.stamp == stamp and not (opts and opts.force) then
    return cb(hit.tasks)
  end
  local done = false
  local ok = pcall(make.list, file, function(tasks)
    if done then
      return
    end
    done = true
    M.cache[file] = { stamp = stamp, tasks = M.sort(tasks) }
    cb(M.cache[file].tasks)
  end)
  if not ok and not done then
    log.warn "Tasks: make could not be read"
  end
end

--- What gets remembered about a task (argv, cwd, the arguments): enough to run it again without asking make anything
---@param task Task
---@param extra string?
---@return table
local function entry(task, extra)
  return { name = task.name, cmd = task.cmd, cwd = task.cwd, extra = extra ~= "" and extra or nil }
end

--- Runs a task and remembers it as the last one of its project
---@param task Task
---@param extra string?
function M.run(task, extra)
  extra = extra and vim.trim(extra) or ""
  require("tasks.exec").run(task, extra, function()
    store.set_last(util.root(task.cwd), entry(task, extra))
  end)
end

--- Asks for the arguments to put after the target (`PKG=./x`, `-j8`), then `cb(text)`
---@param task Task
---@param default string?
---@param cb fun(text: string)
function M.ask(task, default, cb)
  local modal = require "utils.modal"
  local lines = {
    { { require("tasks.exec").line(task), modal.hl.folder } },
    { { vim.fn.fnamemodify(task.cwd, ":~"), modal.hl.muted } },
  }
  -- after the picker has finished closing: it leaves insert mode on its way out, which would undo the modal's own
  vim.schedule(function()
    modal.input(lines, { title = "Arguments for " .. task.name, confirm = "Run", default = default }, cb)
  end)
end

--- Shows what the target would do, without doing it (not remembered as the last one)
---@param task Task
function M.dry(task)
  require("tasks.exec").run(vim.tbl_extend("force", task, { cmd = task.dry, name = task.name .. " (dry run)" }))
end

--- The picker. `opts.dry` makes Enter a dry run; `opts.force` skips the cache
---@param opts { dry: boolean?, force: boolean? }?
function M.pick(opts)
  opts = opts or {}
  local dir = M.dir()
  local file = M.need(dir)
  if not file then
    return
  end
  M.collect(file, { force = opts.force }, function(tasks)
    if #tasks == 0 then
      return log.info("Tasks: no targets in " .. vim.fn.fnamemodify(file, ":~"))
    end
    require("tasks.picker").open(tasks, {
      title = (opts.dry and "Dry run · " or "Make · ") .. vim.fn.fnamemodify(vim.fs.dirname(file), ":~"),
      on_select = opts.dry and M.dry or M.run,
      on_args = function(task)
        M.ask(task, "", function(text)
          M.run(task, text)
        end)
      end,
      on_dry = M.dry,
      on_refresh = function()
        M.pick { dry = opts.dry, force = true }
      end,
    })
  end)
end

--- The last target of this project (else the last anywhere), again. `opts.ask` edits its arguments first
---@param opts { ask: boolean? }?
function M.last(opts)
  if not M.need(M.dir()) then
    return
  end
  local last = store.get_last(util.root(M.dir()))
  if not last then
    return log.info "Tasks: nothing has run yet (<leader>Rr picks a target)"
  end
  if opts and opts.ask then
    return M.ask(last, last.extra, function(text)
      M.run(last, text)
    end)
  end
  M.run(last, last.extra)
end

--- A bare `make`: whatever the Makefile's default goal is
function M.default()
  local file = M.need(M.dir())
  if file then
    M.run { name = "make", cmd = { "make" }, cwd = vim.fs.dirname(file) }
  end
end

--- Ctrl-C to the running task
function M.stop()
  if M.need(M.dir()) and not require("tasks.exec").stop() then
    log.info "Tasks: nothing is running"
  end
end

--- Shows (or hides) the terminal the tasks run in
function M.output()
  if M.need(M.dir()) then
    vim.cmd("ToggleTerm direction=" .. require("utils.terminal").direction())
  end
end

--- The errors in the last terminal's output (go, tsc, cargo, python, javac, generic: the agent's own parser, 0 tokens) as
--- the quickfix list
function M.quickfix()
  if not M.need(M.dir()) then
    return
  end
  local text = require("agent.errors.source").terminal(require("core.settings").agent.errors.terminal_lines)
  local errors = text and require("agent.errors.parse").parse(text, { root = util.root(M.dir()) }) or {}
  if #errors == 0 then
    return log.info "Tasks: no file:line errors in the last terminal output"
  end
  vim.fn.setqflist({}, " ", {
    title = "Task output",
    items = vim.tbl_map(function(e)
      return { filename = e.file, lnum = e.lnum, col = e.col, text = e.text, type = e.severity == "warn" and "W" or "E" }
    end, errors),
  })
  vim.cmd "copen"
end

--- Creates a Makefile from a preset (only where there is none)
function M.create()
  require("tasks.create").open(M.dir())
end

return M
