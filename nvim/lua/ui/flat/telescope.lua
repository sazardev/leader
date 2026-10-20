-- ── Flat design: the telescope layout ────────────────────────────────────────
-- Telescope drawn like the landing page's demo: three soft blocks over the editor (results, the prompt under them,
-- the preview on the right) with half-cell gaps between them, each title INSIDE its block as a first row in faint
-- capitals (RESULTS, FIND FILES, PREVIEW), and the previewed file's path in yellow above its code.
-- Plugged in as telescope's `create_layout` (native floats; telescope's own layout can only center titles on a border).
-- `geometry` is pure (tested in scripts/test-flat.sh).
local M = {}

local NARROW = 90 -- below this many columns the preview goes above the list instead of beside it

---@class FlatTelRect
---@field row integer
---@field col integer
---@field width integer
---@field height integer

--- Where each window goes (row/col of the border's top-left corner, content size), for an editor area
--- `cols` x `lines` (lines = rows above the statusline). One row and two columns of editor stay around the frame.
--- `count` (pickers without a preview and a known, short list: choosers) gives a compact block, centered, as tall as
--- the list.
---@param cols integer
---@param lines integer
---@param preview boolean
---@param count? integer
---@return { results: FlatTelRect, prompt: FlatTelRect, preview?: FlatTelRect, side: boolean }
function M.geometry(cols, lines, preview, count)
  local r0, c0 = 1, 2
  local tw, th = math.max(cols - 4, 20), math.max(lines - 2, 10)
  local out = { side = cols >= NARROW }
  if not preview and count and count + 5 < th then
    local w = math.min(tw, 90)
    local h = math.max(count, 3)
    r0 = math.max(1, math.floor((lines - (h + 5)) / 2))
    c0 = math.floor((cols - w) / 2)
    out.results = { row = r0, col = c0, width = w, height = h }
    out.prompt = { row = r0 + h + 2, col = c0, width = w, height = 1 }
    return out
  end
  if preview and out.side then
    local lw = math.floor(tw * 0.46)
    out.results = { row = r0, col = c0, width = lw, height = th - 5 }
    out.prompt = { row = r0 + th - 3, col = c0, width = lw, height = 1 }
    out.preview = { row = r0, col = c0 + lw, width = tw - lw - 2, height = th - 2 }
  elseif preview then
    local ph = math.floor(th * 0.45) -- preview rows, with its title and bottom edge
    out.preview = { row = r0, col = c0, width = tw - 2, height = ph - 2 }
    out.results = { row = r0 + ph, col = c0, width = tw, height = th - ph - 5 }
    out.prompt = { row = r0 + th - 3, col = c0, width = tw, height = 1 }
  else
    out.results = { row = r0, col = c0, width = tw, height = th - 5 }
    out.prompt = { row = r0 + th - 3, col = c0, width = tw, height = 1 }
  end
  out.results.height = math.max(out.results.height, 1)
  return out
end

--- Native border of each block: the top row carries the title, the bottom row is a half cell (the gap);
--- the preview's left column is a half cell too when it sits beside the list.
---@param kind "results"|"prompt"|"preview"
---@param side boolean
local function border(kind, side)
  local pad, edge = { " ", "TelescopePreviewBorder" }, { "▀", "FlatEdge" }
  if kind ~= "preview" then
    return {
      "",
      { " ", "Telescope" .. (kind == "results" and "Results" or "Prompt") .. "Border" },
      "",
      "",
      "",
      edge,
      "",
      "",
    }
  end
  if side then
    return { { "▐", "FlatEdge" }, pad, pad, pad, edge, edge, { "▝", "FlatEdge" }, { "▐", "FlatEdge" } }
  end
  return { pad, pad, pad, pad, edge, edge, edge, pad }
end

--- Titles in capitals, like the demo's (RESULTS, FIND FILES); one that lists keys (`<C-p> copy prompt`) keeps its case:
--- in capitals `<C-p>` would read as another key
---@param s string?
local function caps(s)
  s = s or ""
  return " " .. (s:find "<[%w%-]+>" and s or s:upper())
end

local function editor_lines()
  return vim.o.lines - vim.o.cmdheight - (vim.o.laststatus ~= 0 and 1 or 0)
end

--- A title that fits its block, cut at the END with `…` (Neovim would cut it from the start: `<C-y> copy all` would read
--- `<y> copy all`)
---@param title string
---@param width integer
---@return string
local function fit_title(title, width)
  if vim.fn.strdisplaywidth(title) <= width then
    return title
  end
  return vim.fn.strcharpart(title, 0, math.max(width - 1, 1)) .. "…"
end

---@param rect FlatTelRect
---@param kind "results"|"prompt"|"preview"
---@param side boolean
---@param title string
local function win_config(rect, kind, side, title)
  return {
    relative = "editor",
    style = "minimal",
    row = rect.row,
    col = rect.col,
    width = rect.width,
    height = rect.height,
    border = border(kind, side),
    title = { { fit_title(title, rect.width - 1), "Telescope" .. kind:gsub("^%l", string.upper) .. "Title" } },
    title_pos = "left",
    zindex = 50,
  }
end

---@param kind "results"|"prompt"|"preview"
local function winhl(kind)
  local part = kind:gsub("^%l", string.upper)
  return ("Normal:Telescope%sNormal,FloatBorder:Telescope%sBorder,FloatTitle:Telescope%sTitle,EndOfBuffer:Telescope%sNormal"):format(
    part,
    part,
    part,
    part
  )
end

--- How many entries a picker's list has, when it is a fixed table (choosers); nil for anything searched live
---@param picker table
---@return integer?
local function count(picker)
  local results = picker.finder and rawget(picker.finder, "results")
  return type(results) == "table" and #results or nil
end

--- The layout telescope mounts (`defaults.create_layout`)
---@param picker table
function M.create_layout(picker)
  local Layout = require "telescope.pickers.layout"
  local titles = {
    results = caps(picker.results_title ~= false and (picker.results_title or "Results") or ""),
    prompt = caps(picker.prompt_title ~= false and (picker.prompt_title or "") or ""),
    preview = caps "Preview",
  }

  local function open(kind, rect, side, enter)
    local buf = vim.api.nvim_create_buf(false, true)
    -- gone with its window: the preview's buffer used to stay behind on every open (a previewer swaps its own in)
    vim.bo[buf].bufhidden = "wipe"
    local win = vim.api.nvim_open_win(buf, enter, win_config(rect, kind, side, titles[kind]))
    vim.wo[win].winhighlight = winhl(kind)
    vim.wo[win].wrap = false
    return Layout.Window { bufnr = buf, winid = win }
  end

  local function close(window)
    if window and vim.api.nvim_win_is_valid(window.winid) then
      vim.api.nvim_win_close(window.winid, true)
    end
  end

  return Layout {
    picker = picker,
    mount = function(self)
      local g =
        M.geometry(vim.o.columns, editor_lines(), picker.previewer ~= nil and picker.previewer ~= false, count(picker))
      self.results = open("results", g.results, g.side, false)
      if g.preview then
        self.preview = open("preview", g.preview, g.side, false)
        local win = self.preview.winid
        vim.w[win].flat_preview = true
        self.preview.border.change_title = function(_, title)
          M.set_path(win, title)
        end
      end
      self.prompt = open("prompt", g.prompt, g.side, true)
    end,
    unmount = function(self)
      close(self.results)
      close(self.preview)
      close(self.prompt)
      local prompt_buf = self.prompt.bufnr
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(prompt_buf) then
          pcall(vim.api.nvim_buf_delete, prompt_buf, { force = true })
        end
      end)
      if vim.api.nvim_buf_is_valid(self.results.bufnr) then
        pcall(vim.api.nvim_buf_delete, self.results.bufnr, { force = true })
      end
    end,
    update = function(self)
      local g = M.geometry(vim.o.columns, editor_lines(), self.preview ~= nil, count(picker))
      for _, kind in ipairs { "results", "prompt", "preview" } do
        local w = self[kind]
        if w and g[kind] and vim.api.nvim_win_is_valid(w.winid) then
          vim.api.nvim_win_set_config(w.winid, win_config(g[kind], kind, g.side, titles[kind]))
        end
      end
    end,
  }
end

--- The previewed file's path, yellow, as the preview's first row (its winbar)
---@param win integer
---@param path string?
function M.set_path(win, path)
  if win and vim.api.nvim_win_is_valid(win) then
    local text = (" " .. (path or "")):gsub("%%", "%%%%")
    vim.wo[win].winbar = "%#TelescopePreviewPath#" .. text
  end
end

--- The file an entry previews, or nil when the preview is not a file (agent history, help, commands...)
---@param entry table?
---@return string?
local function file_of(entry)
  if not entry then
    return nil
  end
  local ok, path = pcall(require("telescope.from_entry").path, entry, false, false)
  if ok and type(path) == "string" and path ~= "" and vim.fn.filereadable(path) == 1 then
    return path
  end
end

--- A file preview shows its path in yellow on top, line numbers (faint, never the yellow current number) and, only
--- when the entry points at a line (grep, diagnostics, symbols), that whole row in the yellow veil. Other previews
--- (agent history, help) are left as their picker drew them.
function M.on_preview_loaded()
  local win = vim.fn.bufwinid(vim.api.nvim_get_current_buf())
  if win == -1 then
    return
  end
  local entry = require("telescope.actions.state").get_selected_entry()
  local path = file_of(entry)
  if not path then
    return
  end
  -- the path line again: a preview buffer shown before brings back its own (older) winbar
  if vim.w[win].flat_preview then
    M.set_path(win, vim.fn.fnamemodify(path, ":."))
  end
  local wo = vim.wo[win]
  wo.number = true
  wo.numberwidth = 4
  wo.cursorline = entry.lnum ~= nil
  wo.cursorlineopt = "line"
  wo.winhighlight = winhl "preview"
    .. ",CursorLine:TelescopePreviewLine,LineNr:TelescopePreviewLineNr,CursorLineNr:TelescopePreviewLineNr"
end

return M
