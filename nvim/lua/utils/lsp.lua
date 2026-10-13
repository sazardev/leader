-- ── LSP navigation with clear messages ────────────────────────────────────────
-- vim.lsp.buf.definition() & co. throw an error with "Press ENTER" when the
-- buffer has no server (markdown, yaml...), the server is still starting or doesn't
-- support the method. Here each case is explained in one line.
local log = require "utils.log"
local nav = require "utils.navigation"

local M = {}

--- Does any client of the buffer support `method`? If not, warns why and returns false.
---@param method string
---@param what string action, for the message ("go to definition"...)
---@return boolean
local function supported(method, what)
  local buf = vim.api.nvim_get_current_buf()

  if #vim.lsp.get_clients { bufnr = buf, method = method } > 0 then
    return true
  end

  local clients = vim.lsp.get_clients { bufnr = buf }
  if #clients == 0 then
    log.warn(("No LSP for this file (%s): can't %s"):format(vim.bo[buf].filetype, what))
    return false
  end

  local names = table.concat(
    vim.tbl_map(function(client)
      return client.name
    end, clients),
    ", "
  )
  local starting = vim.tbl_filter(function(client)
    return not client.initialized
  end, clients)

  if #starting > 0 then
    log.warn(("%s is still starting; try again in a few seconds"):format(names))
  else
    log.warn(("%s doesn't support: %s"):format(names, what))
  end
  return false
end

--- Common picker options: no icons, always a list (even with 1 result).
--- Vertical layout: results at full width (doesn't truncate lines) and
--- preview below.
local PICKER = {
  disable_devicons = true,
  jump_type = "never",
  show_line = true,
  fname_width = 40,
  layout_strategy = "vertical",
  layout_config = { preview_height = 0.5, preview_cutoff = 1, mirror = false },
}

--- Picker options that record the Enter jump so you can go back with <Esc>.
---@param origin nav.Origin
local function with_back(origin)
  return vim.tbl_extend("force", PICKER, {
    attach_mappings = function()
      require("telescope.actions").select_default:enhance {
        post = function()
          nav.landed(origin)
        end,
      }
      return true
    end,
  })
end

--- Go to the definition of the symbol under the cursor. A single target: jumps and <Esc>
--- goes back; several: quickfix (like the default behaviour).
function M.goto_definition()
  if not supported("textDocument/definition", "go to definition") then
    return
  end

  local origin = nav.origin()
  vim.lsp.buf.definition {
    on_list = function(result)
      if #result.items == 0 then
        return log.info(("Definition of '%s' not found"):format(vim.fn.expand "<cword>"))
      end
      if #result.items > 1 then
        vim.fn.setqflist({}, " ", result)
        return vim.cmd "botright copen"
      end
      local client = vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" })[1]
      vim.lsp.util.show_document(result.items[1].user_data, client.offset_encoding, { reuse_win = true, focus = true })
      nav.landed(origin)
    end,
  }
end

--- Ask the server first: if there are no results it explains in one line (Telescope's
--- generic message doesn't say why it's empty or which key to use);
--- if there are, it opens the picker.
---@param method string
---@param extra? table extra params fields (e.g. context)
---@param empty_hint string message when there are no results (%s = symbol)
---@param open fun()
local function lookup(method, extra, empty_hint, open)
  local client = vim.lsp.get_clients({ bufnr = 0, method = method })[1]
  local params = vim.tbl_extend("force", vim.lsp.util.make_position_params(0, client.offset_encoding), extra or {})
  local symbol = vim.fn.expand "<cword>"

  vim.lsp.buf_request_all(0, method, params, function(results)
    local count = 0
    for _, response in pairs(results) do
      local result = response.result
      if result then
        count = count + (vim.islist(result) and #result or 1)
      end
    end
    if count == 0 then
      log.info(empty_hint:format(symbol))
    else
      open()
    end
  end)
end

--- Where the symbol under the cursor is used: filterable list with preview;
--- Enter jumps, <C-q> sends it to quickfix. Doesn't include the declaration.
function M.references()
  if not supported("textDocument/references", "find references") then
    return
  end
  local origin = nav.origin()
  lookup(
    "textDocument/references",
    { context = { includeDeclaration = false } },
    "'%s' is not used anywhere else",
    function()
      require("telescope.builtin").lsp_references(vim.tbl_extend("force", with_back(origin), { include_declaration = false }))
    end
  )
end

--- Ctrl+click: moves the cursor to the clicked point and jumps to the definition.
--- In non-code windows (nvim-tree, dashboard...) it only moves the cursor.
function M.goto_definition_at_mouse()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then
    return
  end
  vim.api.nvim_set_current_win(pos.winid)
  pcall(vim.api.nvim_win_set_cursor, pos.winid, { pos.line, math.max(pos.column - 1, 0) })

  if vim.bo[vim.api.nvim_win_get_buf(pos.winid)].buftype == "" then
    M.goto_definition()
  end
end

return M
