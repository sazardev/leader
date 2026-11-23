-- ── Python cleanup facade (<leader>pK, :PyClean…) ─────────────────────────────
-- One module per responsibility: `imports.lua` is pure; this file only edits
-- buffers and, for unused variables (which need a real Python parser), asks ruff.
local M = {}

local imports = require "pyclean.imports"
local log = require "utils.log"

local function cfg()
  local ok, settings = pcall(require, "core.settings")
  return ok and settings.python and settings.python.clean or {}
end

local function get(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

--- Replace the buffer, keeping the cursor on the text that was being edited.
---@return boolean changed
local function apply_lines(buf, new)
  local old = get(buf)
  if vim.deep_equal(old, new) then
    return false
  end
  local view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
  local delta = #new - #old
  if delta ~= 0 then
    view.lnum = math.max(1, view.lnum + delta)
    view.topline = math.max(1, view.topline + delta)
    vim.fn.winrestview(view)
  end
  return true
end

local function report(name, count)
  if count > 0 then
    log.info(("Python clean: %s %d"):format(name, count))
  end
end

--- Remove imports whose names never appear elsewhere in the file.
function M.remove_unused(buf)
  local removed, lines = imports.remove_unused(get(buf))
  if apply_lines(buf, lines) then
    report("removed unused imports", #removed)
    return #removed
  end
  log.info "Python clean: no unused imports"
  return 0
end

--- Sort imports into stdlib / third-party / local sections and dedupe them.
function M.sort(buf)
  local lines, duplicates = imports.sort(get(buf))
  if apply_lines(buf, lines) then
    report("deduplicated imports", duplicates)
    return duplicates
  end
  log.info "Python clean: imports are already sorted"
  return 0
end

--- Add the canonical import of every standard alias used without one.
function M.add_missing(buf)
  local added = imports.missing(get(buf))
  if #added == 0 then
    log.info "Python clean: no missing imports"
    return 0
  end
  local lines = require("utils.pyimports").apply_to_lines(get(buf), added)
  apply_lines(buf, lines)
  report("added missing imports", #added)
  return #added
end

--- All the safe steps at once. `silent` is used by the save hook.
---@return table counts
function M.clean(buf, silent)
  local lines, counts = imports.clean(get(buf))
  apply_lines(buf, lines)
  if not silent then
    report("removed unused imports", #counts.removed)
    report("deduplicated imports", counts.duplicates)
    report("added missing imports", #counts.added)
    if #counts.removed + counts.duplicates + #counts.added == 0 then
      log.info "Python clean: imports are already clean"
    end
  end
  return counts
end

local function ruff_bin()
  local path = vim.fn.exepath "ruff"
  if path ~= "" then
    return path
  end
  local mason = vim.fn.stdpath("data") .. "/mason/bin/ruff"
  return vim.fn.executable(mason) == 1 and mason or nil
end

--- Ruff's F841 fix is marked unsafe (the assigned expression can have side
--- effects), so this one is an explicit command, never part of the save hook.
function M.remove_unused_vars(buf)
  local bin = ruff_bin()
  if not bin then
    return log.warn "Python clean: ruff is not installed (uv add --dev ruff, or Mason)"
  end
  local text = table.concat(get(buf), "\n") .. "\n"
  local name = vim.api.nvim_buf_get_name(buf)
  local filename = name ~= "" and name or "buffer.py"
  vim.system({
    bin, "check", "--select", "F841", "--fix", "--unsafe-fixes",
    "--stdin-filename", filename, "-",
  }, { stdin = text, text = true }, function(out)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local stdout = out.stdout or ""
      if stdout == "" then
        return log.warn("Python clean: ruff " .. vim.trim(out.stderr or "failed"))
      end
      local fixed = vim.split(stdout, "\n", { plain = true })
      if fixed[#fixed] == "" then
        table.remove(fixed)
      end
      if apply_lines(buf, fixed) then
        log.info "Python clean: removed unused variables (F841)"
      else
        log.info "Python clean: no unused variables"
      end
    end)
  end)
end

--- The save hook: only the conservative, 0-token steps.
function M.on_save(buf)
  if cfg().on_save == false then
    return
  end
  M.clean(buf, true)
end

--- Toggle the save hook and remember the choice where the settings panel does.
function M.toggle()
  local store = require "prefs.store"
  local on = cfg().on_save == false
  store.save("python.clean.on_save", on)
  local ok, settings = pcall(require, "core.settings")
  if ok and settings.python and settings.python.clean then
    settings.python.clean.on_save = on
  end
  log.info("Python clean: on save " .. (on and "on" or "off"))
end

return M
