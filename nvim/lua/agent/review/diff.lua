-- ── A staged diff the model can point into ───────────────────────────────────
-- `git diff --cached` as the model reads it: one `## path` per file, and every line numbered with its position in the NEW
-- file (`+L13` added, ` L12` unchanged context, `-` removed, with no number): findings come back as `path:line`, and
-- those lines are where the diagnostics will land. Pure: raw text in, structure and rendering out.
local M = {}

---@class AgentDiffLine
---@field k "+"|"-"|" "
---@field n integer? line in the new file (nil for removed lines)
---@field text string

---@class AgentDiffFile
---@field path string
---@field status "modified"|"new"|"deleted"|"binary"
---@field hunks { start: integer, lines: AgentDiffLine[] }[]

---@param raw string output of `git diff --cached -U1 --no-color --no-ext-diff --no-renames`
---@return AgentDiffFile[]
function M.parse(raw)
  local files, file, hunk, n = {}, nil, nil, 0
  for _, line in ipairs(vim.split(raw, "\n", { plain = true })) do
    local path = line:match "^diff %-%-git a/.- b/(.+)$"
    if path then
      file = { path = path, status = "modified", hunks = {} }
      files[#files + 1] = file
      hunk = nil
    elseif file then
      local start = line:match "^@@ %-%d+,?%d* %+(%d+),?%d* @@"
      if line:match "^new file mode" then
        file.status = "new"
      elseif line:match "^deleted file mode" then
        file.status = "deleted"
      elseif line:match "^Binary files" or line:match "^GIT binary patch" then
        file.status = "binary"
      elseif start then
        n = tonumber(start) or 1
        hunk = { start = n, lines = {} }
        file.hunks[#file.hunks + 1] = hunk
      elseif hunk then
        local k, text = line:sub(1, 1), line:sub(2)
        if k == "+" then
          hunk.lines[#hunk.lines + 1] = { k = "+", n = n, text = text }
          n = n + 1
        elseif k == " " then
          hunk.lines[#hunk.lines + 1] = { k = " ", n = n, text = text }
          n = n + 1
        elseif k == "-" then
          hunk.lines[#hunk.lines + 1] = { k = "-", text = text }
        end
      end
    end
  end
  return files
end

--- Added lines of a file, `{ n, text }`
---@param file AgentDiffFile
---@return { n: integer, text: string }[]
function M.added(file)
  local out = {}
  for _, hunk in ipairs(file.hunks) do
    for _, l in ipairs(hunk.lines) do
      if l.k == "+" then
        out[#out + 1] = { n = l.n, text = l.text }
      end
    end
  end
  return out
end

---@param file AgentDiffFile
---@return string
local function render_file(file)
  local out = { "## " .. file.path .. (file.status == "new" and " (new)" or "") }
  for _, hunk in ipairs(file.hunks) do
    for _, l in ipairs(hunk.lines) do
      if l.k == "-" then
        out[#out + 1] = "-    " .. l.text
      else
        out[#out + 1] = ("%sL%d %s"):format(l.k, l.n, l.text)
      end
    end
  end
  return table.concat(out, "\n")
end

--- The text for the model, within `max` characters (split among the files: one huge file does not leave the rest without a
--- diff). Skips deleted, binary and noisy files (`is_noise`), which are listed by name only.
---@param files AgentDiffFile[]
---@param max integer
---@param is_noise fun(path: string): boolean
---@return string text, { files: integer, chars: integer, truncated: boolean, skipped: string[] }
function M.render(files, max, is_noise)
  local sized, skipped, total = {}, {}, 0
  for _, f in ipairs(files) do
    if f.status == "deleted" or f.status == "binary" or is_noise(f.path) or #f.hunks == 0 then
      skipped[#skipped + 1] = f.path
    else
      local text = render_file(f)
      sized[#sized + 1] = { file = f, text = text, size = #text }
      total = total + #text
    end
  end
  local by_size = vim.list_slice(sized)
  table.sort(by_size, function(a, b)
    return a.size < b.size
  end)
  local left, truncated = max, false
  for i, s in ipairs(by_size) do
    local share = math.max(300, math.floor(left / (#by_size - i + 1)))
    if s.size > share then
      s.text = s.text:sub(1, share) .. "\n[… cut]"
      truncated = true
    end
    left = left - math.min(s.size, share)
  end
  local parts = vim.tbl_map(function(s)
    return s.text
  end, sized)
  return table.concat(parts, "\n"), { files = #sized, chars = total, truncated = truncated, skipped = skipped }
end

return M
