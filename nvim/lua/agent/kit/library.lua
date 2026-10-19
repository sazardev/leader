-- ── Project kit: the whole library in one search (<leader>aS/) ───────────────
-- Every preset (stacks, designs, their add-ons, principles) in one Telescope list with its preview, searched by name, id,
-- category and description. On the one under the cursor:
--   ⏎    use it: a stack or a design opens its customize step (best picks checked); an add-on is merged into the STACK.md or
--        DESIGN.md there; a principle is added to STACK.md's principles
--   ^e   embed: its text under the cursor of the buffer you came from (a prefab section for any Markdown, a design token
--        table for a doc…)
--   ^y   copy its text to the clipboard
--   ^o   open the preset file itself (to read it whole or make your own from it)
local compose = require "agent.kit.compose"
local log = require "utils.log"
local presets = require "agent.kit.presets"

local M = {}

---@class KitEntry
---@field kind "stack"|"design"|"stack add-on"|"design add-on"|"principle"|"recipe"
---@field preset KitPreset
---@field category string?   stack/design category id
---@field where string       what the list shows next to the name ("backend", "deploy", …)

--- Every preset of the library, kind by kind (pure but for reading the files)
---@param dir string?
---@return KitEntry[]
function M.entries(dir)
  local out = {}
  for _, kind in ipairs { "stack", "design" } do
    for _, c in ipairs(presets.categories(dir, kind)) do
      for _, p in ipairs(presets.list(kind .. "/" .. c.id, dir)) do
        out[#out + 1] = { kind = kind, preset = p, category = c.id, where = c.label }
      end
    end
  end
  for _, spec in ipairs {
    { kind = "stack add-on", folder = "addons", axes = presets.AXES },
    { kind = "design add-on", folder = "design-addons", axes = presets.DESIGN_AXES },
  } do
    for _, axis in ipairs(spec.axes) do
      for _, p in ipairs(presets.list(spec.folder .. "/" .. axis.id, dir)) do
        out[#out + 1] = { kind = spec.kind, preset = p, where = axis.label }
      end
    end
  end
  for _, p in ipairs(presets.list("principles", dir)) do
    out[#out + 1] = { kind = "principle", preset = p, where = p.core and "core" or "" }
  end
  for _, r in ipairs(require("agent.kit.recipes").all(dir)) do
    out[#out + 1] = { kind = "recipe", preset = r, where = r.group }
  end
  return out
end

---@param root string
---@param file string
---@return string? text, string path
local function doc(root, file)
  local path = root .. "/" .. file
  return require("utils.project").read(path), path
end

---@param path string
---@param text string
local function save(path, text)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
    return log.warn("Setup: " .. vim.fs.basename(path) .. " has unsaved changes: save them first")
  end
  local f, err = io.open(path, "w")
  if not f then
    return log.warn("Setup: " .. tostring(err))
  end
  f:write(text)
  f:close()
  vim.cmd.checktime()
  vim.cmd.edit(vim.fn.fnameescape(path))
  return true
end

--- ⏎ on an entry
---@param e KitEntry
function M.use(e)
  local kit = require "agent.kit"
  if e.kind == "stack" then
    return kit.stack { preset = e.preset, category = e.category }
  elseif e.kind == "design" then
    return kit.design { preset = e.preset, category = e.category }
  elseif e.kind == "recipe" then -- its values, then its build (<leader>aSr)
    return require("agent.kit.recipes").start(e.preset --[[@as KitRecipe]])
  end
  local root = require("agent.kit.snapshot").root()
  local file = (e.kind == "design add-on") and "DESIGN.md" or "STACK.md"
  local text, path = doc(root, file)
  if not text then
    return log.info(("Setup: there is no %s yet (<leader>aS%s)"):format(file, file == "STACK.md" and "t" or "d"))
  end
  local new
  if e.kind == "principle" then
    local have = {}
    for _, name in ipairs(compose.principles_in(text)) do
      have[name:lower()] = true
    end
    have[e.preset.name:lower()] = true
    new = compose.set_principles(
      text,
      vim.tbl_filter(function(p)
        return have[p.name:lower()]
      end, presets.list "principles")
    )
  else
    new = compose.merge(text, e.preset.body)
  end
  if new == text then
    return log.info(("Setup: %s already has %s"):format(file, e.preset.name))
  end
  if save(path, new) then
    log.info(("Setup: %s · %s"):format(file, e.preset.name))
  end
end

--- ^e on an entry: its text under the cursor of the window the search was opened from
---@param e KitEntry
---@param win integer
function M.embed(e, win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.bo[buf].modifiable then
    return log.warn "Setup: that buffer cannot be edited"
  end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local lines = vim.split(vim.trim(e.preset.body), "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
  vim.api.nvim_set_current_win(win)
  log.info(("Setup: %s embedded (%d lines)"):format(e.preset.name, #lines))
end

--- <leader>aS/: the library
function M.open()
  local origin = vim.api.nvim_get_current_win()
  local entries = M.entries()
  local width = 0
  for _, e in ipairs(entries) do
    width = math.max(width, vim.fn.strdisplaywidth(e.preset.name))
  end
  require("tasks.picker").choose(
    vim.tbl_map(function(e)
      local where = e.kind .. (e.where ~= "" and (" · " .. e.where:lower()) or "")
      return {
        label = e.preset.name,
        desc = where,
        path = e.preset.path,
        value = e,
        search = e.preset.id .. " " .. e.preset.desc .. " " .. (e.category or ""),
      }
    end, entries),
    {
      title = ("Library · %d presets"):format(#entries),
      hint = "⏎ use · ^e embed · ^y copy · ^o open",
      preview = true,
      width = math.min(width + 2, 34),
      maps = {
        {
          "<C-e>",
          function(e)
            M.embed(e, origin)
          end,
        },
        {
          "<C-y>",
          function(e)
            vim.fn.setreg("+", e.preset.body)
            vim.fn.setreg('"', e.preset.body)
            log.info(("Setup: %s copied"):format(e.preset.name))
          end,
        },
        {
          "<C-o>",
          function(e)
            vim.cmd.edit(vim.fn.fnameescape(e.preset.path))
          end,
        },
      },
    },
    M.use
  )
end

return M
