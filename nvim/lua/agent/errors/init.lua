-- ── Fix from output ──────────────────────────────────────────────────────────
-- A build failed; you run `<leader>ao`. The errors are read from the last terminal (or the quickfix list, or a command
-- you type with `<leader>aO`), parsed by Neovim's own `errorformat` (0 tokens), grouped by the function they point into
-- and sent as ONE confirmed batch: the model only sees the errors of the piece it is fixing, not the whole output.
local log = require "utils.log"
local parse = require "agent.errors.parse"
local settings = require("core.settings").agent.errors
local source = require "agent.errors.source"

local M = {}

---@param file string absolute
---@return integer buf loaded, with its filetype, ready for treesitter
local function load(file)
  local buf = vim.fn.bufadd(file)
  vim.fn.bufload(buf)
  if vim.bo[buf].filetype == "" then
    local ft = vim.filetype.match { buf = buf, filename = file }
    if ft then
      vim.bo[buf].filetype = ft
    end
  end
  return buf
end

--- Batch items for `errors`: one per function that holds any, each with its own errors as the extra section
---@param errors AgentToolError[]
---@param label string?
---@return AgentBatchItem[]
function M.items(errors, label)
  local by_file, order = {}, {}
  for _, e in ipairs(vim.list_slice(errors, 1, settings.max_errors)) do
    if not by_file[e.file] then
      by_file[e.file] = {}
      order[#order + 1] = e.file
    end
    table.insert(by_file[e.file], e)
  end
  local items = {}
  for _, file in ipairs(order) do
    local buf = load(file)
    for _, item in ipairs(require("agent.fixall").items(buf, parse.as_diagnostics(by_file[file]))) do
      item.extra = require("agent.errors.action").section(item.diags or {}, label)
      items[#items + 1] = item
    end
  end
  return items
end

--- Runs the batch for `errors`
---@param errors AgentToolError[]
---@param label string where they came from
function M.fix(errors, label)
  if #errors == 0 then
    return log.info "Agent: no errors to fix"
  end
  local items = M.items(errors, label)
  if #items == 0 then
    return log.info "Agent: those errors do not point into code the agent can edit"
  end
  local hl = require("utils.modal").hl
  require("agent.batch").run {
    title = "fix output",
    action = require("agent.errors.action").build "fix output",
    items = items,
    header = { { { ("%d error%s from %s"):format(#errors, #errors == 1 and "" or "s", label), hl.warn } } },
  }
end

--- `<leader>ao`: the errors the last terminal or the quickfix list hold
function M.run()
  local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
  local errors, label = source.auto(root, { terminal_lines = settings.terminal_lines })
  if #errors == 0 then
    return log.info "Agent: no errors in the last terminal or the quickfix list (run your build there first, or <leader>aO to run a command)"
  end
  M.fix(errors, label)
end

--- `<leader>aO`: asks for a command, runs it and fixes what it prints
function M.run_command()
  local abs = vim.api.nvim_buf_get_name(0)
  local ft = vim.bo.filetype
  local guess = abs ~= "" and require("agent.verify.build").command_for(abs, ft, "auto") or nil
  local hl = require("utils.modal").hl
  require("utils.modal").input({ { { "Command to run in the project:", hl.muted } } }, {
    title = "Fix output",
    default = guess and guess.label or "",
  }, function(text)
    if text == "" then
      return
    end
    local cwd = (guess and guess.cwd) or vim.fs.root(0, ".git") or vim.fn.getcwd()
    -- through the user's own shell: what they type may be a pipeline or `a && b`
    local cmd = { vim.o.shell, vim.o.shellcmdflag, text }
    log.info(("Agent: running `%s`…"):format(text))
    source.command({ cmd = cmd, cwd = cwd, label = text }, function(output, err)
      if err then
        return log.warn("Agent: " .. err)
      end
      local errors = parse.parse(output or "", { root = cwd })
      if #errors == 0 then
        return log.info(("Agent: `%s` printed no errors I can place in the code"):format(text))
      end
      M.fix(errors, ("`%s`"):format(text))
    end)
  end)
end

return M
