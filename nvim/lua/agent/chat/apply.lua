-- ── Apply the full files a Write answer returns ─────────────────────────────
-- The Write profile asks the model for complete files in fenced blocks whose
-- info string carries the path (```go: main.go). This module finds those blocks,
-- resolves them inside the project and writes the ones that already exist,
-- keeping the buffer and the disk in sync. Parsing is pure; writing needs the
-- editor and is done only after the turn settles.
local paths = require "files.paths"

local M = {}

--- Fenced blocks whose info string is `lang: path` (or a bare path).
---@param text string
---@return table[] { path: string, lang: string, body: string[] }
function M.blocks(text)
  local out = {}
  local lines = vim.split(((text or ""):gsub("\r\n", "\n")), "\n", { plain = true })
  local i = 1
  while i <= #lines do
    local info = lines[i]:match "^%s*```%s*(.-)%s*$"
    if info then
      local lang, path = info:match "^([%w%+%._%-]*):%s*(.+)$"
      if not path and info:find "[/%.]" and not info:find "%s" then
        lang, path = "", info
      end
      local body = {}
      local j = i + 1
      while j <= #lines and not lines[j]:match "^%s*```%s*$" do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      if path and path ~= "" and j <= #lines and #body > 0 then
        out[#out + 1] = { path = vim.trim(path), lang = lang or "", body = body }
      end
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

--- An answer that is a diff or an edit-block proposal is not a full file.
---@param body string[]
---@return boolean
local function not_a_file(body)
  local first = body[1] or ""
  if first:match "^diff %-%-git " or first:match "^%-%-%- [ab]/" then
    return true
  end
  for _, line in ipairs(body) do
    if line:match "^<<<<<<< SEARCH" or line:match "^>>>>>>> REPLACE" then
      return true
    end
  end
  return false
end

--- Resolve a model path inside the project. Absolute, escaping, generated and
--- binary-looking paths are refused.
---@param root string
---@param name string
---@return string? full, string? why
function M.resolve(root, name)
  root = vim.fs.normalize(root or "")
  name = vim.trim(name or ""):gsub("^%./", "")
  if name == "" or name:find "[%z\n\r]" then
    return nil, "empty path"
  end
  if name:sub(1, 1) == "/" or name:sub(1, 1) == "~" then
    return nil, "not a relative project path"
  end
  local ok, why = paths.valid(name)
  if not ok then
    return nil, why
  end
  local full = vim.fs.normalize(paths.resolve(root, name))
  if not paths.inside(full, root) then
    return nil, "outside the project"
  end
  if require("utils.generated").is_generated(full) then
    return nil, "generated file"
  end
  return full
end

--- The loaded buffer for `path`, if any.
---@param path string
---@return integer?
local function loaded_buffer(path)
  local target = vim.fs.normalize(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" then
      if vim.fs.normalize(vim.api.nvim_buf_get_name(buf)) == target then
        return buf
      end
    end
  end
  return nil
end

--- Write one file. A loaded, unmodified buffer is edited in place (undo works
--- and the editor follows); a closed file is backed up to the trash first.
---@param full string
---@param body string[]
---@return boolean? ok, string? why, "changed"|"unchanged"?
function M.write(full, body)
  local buf = loaded_buffer(full)
  if buf then
    if vim.bo[buf].modified then
      return nil, "has unsaved changes"
    end
    local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if table.concat(current, "\n") == table.concat(body, "\n") then
      return true, nil, "unchanged"
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
    vim.bo[buf].modified = true
    local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
      vim.cmd "silent write"
    end)
    if not ok then
      return nil, tostring(err)
    end
    return true, nil, "changed"
  end

  local current = vim.fn.readfile(full)
  if table.concat(current, "\n") == table.concat(body, "\n") then
    return true, nil, "unchanged"
  end
  local trashed, why = require("files.ops").trash(full)
  if not trashed then
    return nil, why or "could not back up the file"
  end
  local wrote = vim.fn.writefile(body, full)
  if wrote ~= 0 then
    require("files.ops").restore() -- best effort: put the old file back
    return nil, "could not write the file"
  end
  require("files.buffers").refresh_tree()
  return true, nil, "changed"
end

--- Apply every full-file block of `text`.
---@param session table? { root: string }
---@param text string
---@return { files: string[], unchanged: string[], skipped: string[], errors: string[] }
function M.run(session, text)
  local root = vim.fs.normalize((session and session.root) or vim.uv.cwd())
  local out = { files = {}, unchanged = {}, skipped = {}, errors = {} }
  local seen = {}
  for _, block in ipairs(M.blocks(text)) do
    local full, why = M.resolve(root, block.path)
    local name = block.path:gsub("^%./", "")
    if not full then
      out.skipped[#out.skipped + 1] = ("%s (%s)"):format(name, why or "invalid")
    elseif seen[full] then
      -- the same file twice in one answer: the first block wins
    elseif vim.fn.filereadable(full) == 0 then
      out.skipped[#out.skipped + 1] = name .. " (new file)"
    elseif not_a_file(block.body) then
      out.skipped[#out.skipped + 1] = name .. " (diff, not a full file)"
    else
      seen[full] = true
      local ok, err, state = M.write(full, block.body)
      if not ok then
        out.errors[#out.errors + 1] = ("%s: %s"):format(name, tostring(err))
      elseif state == "unchanged" then
        out.unchanged[#out.unchanged + 1] = name
      else
        out.files[#out.files + 1] = name
      end
    end
  end
  return out
end

return M
