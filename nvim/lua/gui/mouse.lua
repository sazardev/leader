-- ── Desktop app: the mouse in the plugins' windows ───────────────────────────
-- utils/mouse.lua gives the config's own windows hover and click; here the same
-- for Telescope (every picker and the palette) and the file tree, wired when
-- their buffers appear, and 'mousemoveevent' following the focus (the app sends
-- the pointer's moves only while it is on).
local mouse = require "utils.mouse"

local M = {}

--- Telescope (the palette, every picker): the row under the pointer is the selection, a click opens it, a click
--- outside its windows closes the picker.
---@param prompt integer the prompt buffer
function M.telescope(prompt)
  local function picker()
    local ok, state = pcall(require, "telescope.actions.state")
    return ok and state.get_current_picker(prompt) or nil
  end
  mouse.on(prompt, {
    modes = { "i", "n" },
    move = function(pos)
      local p = picker()
      if p and pos.winid == p.results_win and pos.line > 0 then
        -- selecting the row under the pointer must not scroll the results (see utils/mouse.follow)
        pcall(function()
          vim.wo[p.results_win].scrolloff = 0
        end)
        pcall(p.set_selection, p, pos.line - 1)
      end
    end,
    press = function(pos)
      local p = picker()
      if not p then
        return
      end
      local actions = require "telescope.actions"
      if pos.winid == p.results_win and pos.line > 0 then
        pcall(p.set_selection, p, pos.line - 1)
        vim.schedule(function()
          actions.select_default(prompt)
        end)
      elseif pos.winid ~= p.prompt_win and pos.winid ~= p.preview_win then
        vim.schedule(function()
          pcall(actions.close, prompt)
        end)
      end
    end,
  })
end

--- The file tree: the row under the pointer lights up, one click opens a file or a folder (like any desktop editor).
---@param buf integer
function M.tree(buf)
  mouse.on(buf, {
    move = function(pos)
      local win = vim.fn.bufwinid(buf)
      if pos.winid == win then
        mouse.follow(win, pos.line)
      end
    end,
    click = function(pos)
      local win = vim.fn.bufwinid(buf)
      if pos.winid == win and pos.line > 0 then
        pcall(vim.api.nvim_win_set_cursor, win, { pos.line, 0 })
        local ok, api = pcall(require, "nvim-tree.api")
        if ok then
          pcall(api.node.open.edit)
        end
      end
    end,
  })
end

---@param group integer
function M.setup(group)
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "FileType" }, {
    group = group,
    callback = function()
      vim.schedule(mouse.sync)
    end,
  })
  -- after the plugins' own buffer mappings (they would replace these)
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "TelescopePrompt", "NvimTree" },
    callback = function(ev)
      vim.schedule(function()
        if ev.match == "TelescopePrompt" then
          M.telescope(ev.buf)
        else
          M.tree(ev.buf)
        end
      end)
    end,
  })
end

return M
