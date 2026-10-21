-- ── What a build is about to throw away (pure, 0 tokens) ─────────────────────
-- A build that replans a project sends the files its new plan no longer lists to the trash. Done silently, a repair can
-- delete the very screens the user liked (cutter lost ~2,600 lines of its design that way) because deleting is the
-- quickest way to a green compile. So before anything is trashed, what is in those files is counted and named: how many
-- lines, which public declarations, which tests name which requirements, and who else uses them. A loss that carries a
-- real declaration, or enough code, is not deleted on the review's Enter alone: it asks, with the list in front of it.
local decls = require "agent.kit.decls"

local M = {}

M.SIGNIFICANT_LINES = 60

---@class BuildLossFile
---@field path string
---@field lines integer
---@field types string[]    public types it declares
---@field values string[]   public functions and constants it declares
---@field used_by string[]  files that stay and mention one of its names
---@field tests string[]    requirements a test in it names ("FR-5")

---@class BuildLoss
---@field files BuildLossFile[]
---@field lines integer
---@field types integer
---@field significant boolean

---@param text string
---@return integer
local function count_lines(text)
  local n = 0
  for _ in (text .. "\n"):gmatch "[^\n]*\n" do
    n = n + 1
  end
  return n - 1
end

--- The inventory of files that would go (pure)
---@param gone table<string, string> path → text of what would be deleted
---@param staying table<string, string> path → text of the source that stays
---@return BuildLoss
function M.describe(gone, staying)
  local paths = vim.tbl_keys(gone)
  table.sort(paths)
  local loss = { files = {}, lines = 0, types = 0, significant = false }
  for _, path in ipairs(paths) do
    local text = gone[path]
    local entry = { path = path, lines = count_lines(text), types = {}, values = {}, used_by = {}, tests = {} }
    local seen_user = {}
    for _, d in ipairs(decls.of(path, text)) do
      table.insert(d.kind == "type" and entry.types or entry.values, d.name)
      for _, user in ipairs(decls.users(d.name, staying, path)) do
        if not seen_user[user] then
          seen_user[user] = true
          entry.used_by[#entry.used_by + 1] = user
        end
      end
    end
    if require("agent.kit.build.verify").is_test(path) then
      for id in text:gmatch "FR%-%d+" do
        if not vim.tbl_contains(entry.tests, id) then
          entry.tests[#entry.tests + 1] = id
        end
      end
      table.sort(entry.tests)
    end
    loss.files[#loss.files + 1] = entry
    loss.lines = loss.lines + entry.lines
    loss.types = loss.types + #entry.types
  end
  loss.significant = loss.types > 0 or loss.lines >= M.SIGNIFICANT_LINES
  return loss
end

--- The lines of the question (and of the review): what goes, in words
---@param loss BuildLoss
---@param max integer?
---@return string[]
function M.lines(loss, max)
  max = max or 8
  local out = {
    ("%d file%s, %d lines, %d public type%s would be deleted"):format(
      #loss.files,
      #loss.files == 1 and "" or "s",
      loss.lines,
      loss.types,
      loss.types == 1 and "" or "s"
    ),
  }
  for i, f in ipairs(loss.files) do
    if i > max then
      out[#out + 1] = ("… and %d more"):format(#loss.files - max)
      break
    end
    local what = {}
    if #f.types > 0 then
      what[#what + 1] = table.concat(vim.list_slice(f.types, 1, 3), ", ")
    end
    if #f.tests > 0 then
      what[#what + 1] = "tests " .. table.concat(vim.list_slice(f.tests, 1, 4), ", ")
    end
    if #f.used_by > 0 then
      what[#what + 1] = "still used by " .. f.used_by[1] .. (#f.used_by > 1 and (" +%d"):format(#f.used_by - 1) or "")
    end
    out[#out + 1] = ("%s · %d lines%s"):format(
      f.path,
      f.lines,
      #what > 0 and (" · " .. table.concat(what, " · ")) or ""
    )
  end
  return out
end

--- Reads what would go from disk (the only impure part)
---@param root string
---@param paths string[]
---@return BuildLoss?
function M.read(root, paths)
  if #paths == 0 then
    return nil
  end
  local read = require("utils.project").read
  local gone, staying = {}, {}
  local going = {}
  for _, p in ipairs(paths) do
    going[p] = true
    gone[p] = read(root .. "/" .. p) or ""
  end
  for _, p in ipairs(require("agent.kit.snapshot").list_files(root)) do
    if not going[p] and decls.is_source(p) then
      local stat = vim.uv.fs_stat(root .. "/" .. p)
      if stat and stat.size <= 96 * 1024 then
        staying[p] = read(root .. "/" .. p) or ""
      end
    end
  end
  return M.describe(gone, staying)
end

return M
