-- ── Find in current file (<leader>fc): dev-mode search with kind filters ──────
-- One picker, five filters: todo (símbolos + líneas), funciones, clases/tipos,
-- variables (ocurrencias de la palabra bajo el cursor) y líneas (el fuzzy viejo).
-- Los símbolos vienen de agent/context/scopes.lua (treesitter, sin LSP ni IA);
-- la variable es la palabra bajo el cursor al abrir. Fallback a líneas sin parser.
local M = {}

---@class FindEntry
---@field kind "function"|"type"|"line"|"var"
---@field name string
---@field lnum integer 1-based
---@field text string
---@field col integer

---@param buf integer
---@return string? lang treesitter o nil
local function lang_of(buf)
  local ft = vim.bo[buf].filetype
  if not ft or ft == "" then
    return nil
  end
  return vim.treesitter.language.get_lang(ft) or ft
end

---@param lines string[]
---@param word string?
---@param i integer
---@param line string
---@return boolean
local function var_hit(word, line)
  if not word or word == "" then
    return false
  end
  return line:find("%f[%w_]" .. word .. "%f[^%w_]") ~= nil
end

---@param filter string "all"|"func"|"type"|"var"|"line"
---@param ctx { symbols: table[], lines: string[], word: string? }
---@return FindEntry[]
local function build(filter, ctx)
  local out = {}
  local sym_line = {}
  if filter == "all" or filter == "func" or filter == "type" then
    for _, s in ipairs(ctx.symbols) do
      local k = s.kind == "function" and "function" or "type"
      if filter == "all" or (filter == "func" and k == "function") or (filter == "type" and k == "type") then
        out[#out + 1] = {
          kind = k,
          name = s.name or "?",
          lnum = s.first,
          text = vim.trim(ctx.lines[s.first] or ""):sub(1, 160),
          col = 0,
        }
        sym_line[s.first] = true
      end
    end
  end
  if filter == "all" or filter == "line" or filter == "var" then
    for i, line in ipairs(ctx.lines) do
      if filter == "var" then
        if var_hit(ctx.word, line) then
          out[#out + 1] = { kind = "var", name = ctx.word, lnum = i, text = vim.trim(line):sub(1, 160), col = 0 }
        end
      elseif filter == "line" then
        if vim.trim(line) ~= "" then
          out[#out + 1] = { kind = "line", name = vim.trim(line):sub(1, 120), lnum = i, text = vim.trim(line):sub(1, 160), col = 0 }
        end
      else -- all: líneas que no sean ya una línea de símbolo (evita duplicados)
        if vim.trim(line) ~= "" and not sym_line[i] then
          out[#out + 1] = { kind = "line", name = vim.trim(line):sub(1, 120), lnum = i, text = vim.trim(line):sub(1, 160), col = 0 }
        end
      end
    end
  end
  return out
end

---@param prompt_bufnr integer
---@param picker table
---@param f string
local function title(picker, f, word)
  local labels = {
    all = "Find in file · all",
    func = "Find in file · functions",
    type = "Find in file · classes",
    var = ("Find in file · variable `%s`"):format(word or "?"),
    line = "Find in file · lines",
  }
  pcall(function()
    picker.prompt_border:change_title(labels[f] or f)
  end)
end

--- Abre el picker. Filtros dentro con C-a/C-f/C-t/C-v/C-l.
function M.open()
  local ok = pcall(require, "telescope")
  if not ok then
    return vim.notify("Find in file needs Telescope", vim.log.levels.WARN)
  end
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  local lang = lang_of(buf)
  local symbols = {}
  if lang and lang ~= "" then
    local ok2, scopes = pcall(require, "agent.context.scopes")
    if ok2 and scopes then
      local ok3, syms = pcall(scopes.symbols, text, lang)
      if ok3 and type(syms) == "table" then
        symbols = syms
      end
    end
  end
  local word = vim.fn.expand "<cword>"
  if not word or not word:match "^[%w_]+$" then
    word = nil
  end
  local ctx = { symbols = symbols, lines = lines, word = word }
  local filter = "all"

  local pickers, finders = require "telescope.pickers", require "telescope.finders"
  local conf = require("telescope.config").values
  local actions, state = require "telescope.actions", require "telescope.actions.state"
  local entry_display = require "telescope.pickers.entry_display"

  local displayer = entry_display.create {
    separator = "  ",
    items = { { width = 5 }, { width = 6 }, { remaining = true } },
  }
  local KINDS = { ["function"] = "ƒ", ["type"] = "⌘", ["var"] = "var", ["line"] = "·" }

  local function finder()
    return finders.new_table {
      results = build(filter, ctx),
      entry_maker = function(e)
        return {
          value = e,
          path = path ~= "" and path or nil,
          lnum = e.lnum,
          col = 1,
          ordinal = (e.name or "") .. " " .. (e.text or "") .. " " .. tostring(e.lnum),
          display = function()
            local tag = KINDS[e.kind] or "·"
            local hl = e.kind == "function" and "Function" or (e.kind == "type" and "Type" or "Comment")
            local body = e.kind == "line" and e.text or ((e.name or "") .. "  " .. (e.text or ""))
            return displayer { { tag, hl }, { tostring(e.lnum), "Comment" }, { body } }
          end,
        }
      end,
    }
  end

  local previewer = conf.grep_previewer {}
  pickers
    .new({}, {
      prompt_title = "Find in file · all",
      results_title = "Enter open · C-a all · C-f func · C-t type · C-v var · C-l lines",
      finder = finder(),
      sorter = conf.generic_sorter {},
      previewer = previewer,
      attach_mappings = function(bufnr, map)
        local function set_filter(f)
          if f == "var" and not ctx.word then
            return vim.notify("No word under cursor for variable search", vim.log.levels.INFO)
          end
          filter = f
          local picker = state.get_current_picker(bufnr)
          picker:refresh(finder(), { reset_prompt = false })
          title(picker, f, ctx.word)
        end
        map({ "i", "n" }, "<C-a>", function()
          set_filter "all"
        end)
        map({ "i", "n" }, "<C-f>", function()
          set_filter "func"
        end)
        map({ "i", "n" }, "<C-t>", function()
          set_filter "type"
        end)
        map({ "i", "n" }, "<C-v>", function()
          set_filter "var"
        end)
        map({ "i", "n" }, "<C-l>", function()
          set_filter "line"
        end)
        actions.select_default:replace(function(prompt_bufnr)
          local entry = state.get_selected_entry(prompt_bufnr)
          actions.close(prompt_bufnr)
          if entry and entry.value then
            vim.schedule(function()
              vim.cmd "normal! m'"
              vim.api.nvim_win_set_cursor(0, { entry.value.lnum, entry.value.col or 0 })
              vim.cmd "normal! zz"
              vim.cmd "normal! zv"
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
