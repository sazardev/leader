-- ── Reusable action factories for the menus ──────────────────────────────────
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local M = {}

--- Action that runs an Ex command
---@param name string
---@return fun()
function M.ex(name)
  return function()
    vim.cmd(name)
  end
end

--- Action that runs `cmd` at the project root; warns if `bin` is missing
---@param bin string required executable
---@param cmd string
---@param markers? string[]
---@return fun()
function M.run(bin, cmd, markers)
  return function()
    if vim.fn.executable(bin) ~= 1 then
      return log.warn(("`%s` is not installed"):format(bin))
    end
    terminal.run(cmd, project.root(markers or { ".git" }))
  end
end

--- Format the buffer with conform (falling back to LSP)
function M.format()
  require("conform").format { lsp_format = "fallback" }
end

--- Apply a code action of type `kind` (e.g. "source.organizeImports")
---@param kind string
---@return fun()
function M.code_action(kind)
  return function()
    vim.lsp.buf.code_action { context = { only = { kind }, diagnostics = {} }, apply = true }
  end
end

return M
