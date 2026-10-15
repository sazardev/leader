-- ── .gitignore (<leader>Gi) ──────────────────────────────────────────────────
-- Looks at what the project is made of (marker files and extensions, `detect.lua`), shows the matching topics already
-- checked (`presets/*.gitignore`: secrets, languages, Docker, Terraform, editor leftovers) and writes the rules. 0 tokens.
-- With a .gitignore already there it ADDS what is missing and never removes or reorders anything (`compose.lua`). When it is
-- done it says which files git already tracks that the new rules would ignore (a committed `.env` is the classic).
local log = require "utils.log"
local compose = require "gitignore.compose"
local detect = require "gitignore.detect"
local presets = require "gitignore.presets"

local M = {}

---@param path string
---@return string?
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

--- What the checklist says next to a topic
---@param preset IgnorePreset
---@param hit IgnoreHit?
---@param missing integer? new rules, when there is a .gitignore to compare with
---@return string
function M.note(preset, hit, missing)
  local why
  if hit and hit.first ~= "" then
    why = "found " .. hit.first .. (hit.count > 1 and (" +" .. (hit.count - 1)) or "")
  elseif hit then
    why = "recommended"
  else
    why = preset.desc or ""
  end
  if missing == 0 then
    return "already in .gitignore"
  elseif missing then
    return ("%s · %d new"):format(why, missing)
  end
  return why
end

--- Writes (or appends) the rules of `chosen`; never overwrites
---@param root string
---@param chosen IgnorePreset[]
---@return string? path, integer added, string? reason
function M.write(root, chosen)
  local target = root .. "/.gitignore"
  local existing = read(target)
  local text, added = compose.build(presets.order(vim.list_slice(chosen)), existing)
  if added == 0 then
    return nil, 0, "nothing to add: .gitignore has all of these rules"
  end
  local f, err = io.open(target, existing and "a" or "w")
  if not f then
    return nil, 0, err
  end
  f:write(text)
  f:close()
  return target, added
end

---@param files string[]
---@return string?
function M.tracked_message(files)
  if #files == 0 then
    return nil
  end
  local shown = vim.list_slice(files, 1, 5)
  local more = #files > #shown and (" (+%d more)"):format(#files - #shown) or ""
  return ("Git: %d tracked file%s match the new rules and stay in git: %s%s. `git rm --cached <file>` stops tracking them"):format(
    #files,
    #files == 1 and "" or "s",
    table.concat(shown, ", "),
    more
  )
end

--- The files git tracks that the current rules would ignore
---@param root string
---@param cb fun(files: string[])
function M.tracked(root, cb)
  local ok = pcall(
    vim.system,
    { "git", "-C", root, "ls-files", "-ci", "--exclude-standard" },
    { text = true },
    function(res)
      local files = {}
      if res.code == 0 then
        for line in (res.stdout or ""):gmatch "[^\n]+" do
          files[#files + 1] = line
        end
      end
      vim.schedule(function()
        cb(files)
      end)
    end
  )
  if not ok then
    cb {}
  end
end

--- The checklist items: what the project looks like first (checked), the rest after
---@param root string
---@param existing string?
---@return table[] items, IgnorePreset[] list (same order)
function M.items(root, existing)
  local cfg = require("core.settings").git.ignore
  local list = presets.list()
  local hits = detect.run(list, detect.scan(root, cfg))
  local seen = existing and compose.rules(existing) or nil

  local on, off = {}, {}
  for _, preset in ipairs(list) do
    local missing = seen and compose.missing(preset, seen) or nil
    local item = {
      label = preset.title,
      desc = M.note(preset, hits[preset.name], missing),
      checked = hits[preset.name] ~= nil and missing ~= 0,
      preset = preset,
    }
    table.insert(item.checked and on or off, item)
  end
  local items = vim.list_extend(on, off)
  return items, vim.tbl_map(function(item)
    return item.preset
  end, items)
end

--- The whole flow: checklist → write → open the file → warn about what git already tracks
---@param root string? the git root (default: the current file's)
function M.open(root)
  root = root or require("commit.git").root()
  if not root then
    return log.warn "Git: not inside a repository"
  end
  local target = root .. "/.gitignore"
  local buf = vim.fn.bufnr(target)
  if buf ~= -1 and vim.bo[buf].modified then
    return log.warn "Git: save .gitignore first, it has unsaved changes"
  end
  local existing = read(target)
  local items, list = M.items(root, existing)
  if #list == 0 then
    return log.warn "Git: no .gitignore presets found"
  end

  require("utils.modal").checklist(items, {
    title = existing and "Update .gitignore" or "Create .gitignore",
    intro = {
      { { vim.fn.fnamemodify(target, ":~"), require("utils.modal").hl.folder } },
      {
        {
          existing and "Adds only the rules it is missing, nothing is removed."
            or "Checked: what this project looks like.",
          require("utils.modal").hl.muted,
        },
      },
      "",
    },
    confirm = existing and "Add rules" or "Create",
    footer = "Space toggle · a all",
  }, function(indexes)
    if #indexes == 0 then
      return
    end
    local chosen = vim.tbl_map(function(i)
      return list[i]
    end, indexes)
    local path, added, why = M.write(root, chosen)
    if not path then
      return log.info("Git: " .. why)
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.cmd.checktime()
    log.info(
      ("Git: %s .gitignore (%d rule%s from %s)"):format(
        existing and "updated" or "created",
        added,
        added == 1 and "" or "s",
        table.concat(
          vim.tbl_map(function(p)
            return p.title
          end, chosen),
          ", "
        )
      )
    )
    M.tracked(root, function(files)
      local msg = M.tracked_message(files)
      if msg then
        log.warn(msg)
      end
    end)
  end)
end

return M
