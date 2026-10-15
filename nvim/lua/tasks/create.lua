-- ── Create a Makefile (<leader>Rc) ───────────────────────────────────────────
-- Only where there is none: pick a language folder (the one the project looks like first), then one of its presets with
-- the Makefile as the preview; it is written to the project root (the git root, else the cwd) and opened. Never overwrites.
local log = require "utils.log"
local make = require "tasks.make"
local presets = require "tasks.presets"
local util = require "tasks.util"

local M = {}

---@param dir string
function M.open(dir)
  local existing = make.detect(dir, util.stop(dir))
  if existing then
    return log.info("Tasks: there is a Makefile already: " .. vim.fn.fnamemodify(existing, ":~"))
  end
  local root = util.root(dir)
  local languages = presets.order(presets.languages(), presets.guess(root, vim.bo.filetype))
  if #languages == 0 then
    return log.warn "Tasks: no Makefile presets found"
  end
  local picker = require "tasks.picker"
  local where = vim.fn.fnamemodify(root, ":~")

  picker.choose(vim.tbl_map(function(lang)
    return { label = lang.label, desc = #lang.presets .. " presets", value = lang }
  end, languages), { title = "Makefile for " .. where }, function(lang)
    picker.choose(vim.tbl_map(function(p)
      return { label = p.name, desc = p.desc, path = p.path, value = p }
    end, lang.presets), { title = lang.label .. " · Makefile for " .. where, preview = true }, function(preset)
      local path, why = presets.write(root, preset)
      if not path then
        return log.warn("Tasks: " .. why)
      end
      vim.cmd.edit(vim.fn.fnameescape(path))
      log.info(("Tasks: created Makefile (%s, %s). <leader>Rr runs its targets"):format(lang.label, preset.name))
    end)
  end)
end

return M
