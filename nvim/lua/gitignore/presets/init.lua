-- ── .gitignore presets ───────────────────────────────────────────────────────
-- `<leader>Gi` writes a .gitignore from the topics that fit the project. A topic is a plain file, `presets/<name>.gitignore`:
-- drop one in and it is discovered. Its shape:
--
--   # Go: compiled binaries, test and profiling output     <- line 1: `Title: what it ignores` (stays in the .gitignore)
--   # detect: go.mod go.work *.go                          <- line 2: what in the project says it applies (not written)
--   # Binaries and build output                            <- the rules, in blocks split by blank lines, each with its why
--   /bin/
--
-- `detect` takes file names (`go.mod`), globs on a name (`*.go`, `.env.*`), folders with a slash (`node_modules/`) and the
-- word `always` (recommended for every project). Matching is done by `gitignore.detect`.
local M = {}

---@class IgnorePreset
---@field name string      file name without extension
---@field title string     what the checklist calls it
---@field desc string?     what it ignores
---@field header string    the first line, as written
---@field detect string[]
---@field body string[]    the rules, one entry per line (blank lines split blocks)
---@field path string

--- Folder of the preset files
---@return string
function M.dir()
  return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
end

--- Reads one preset's text
---@param name string
---@param text string
---@param path string?
---@return IgnorePreset?
function M.parse(name, text, path)
  local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
  local header = lines[1]
  if not header or not header:match "^#%s*%S" then
    return nil
  end
  local title, desc = header:match "^#%s*([^:]+):%s*(.-)%s*$"
  local detect, body = {}, {}
  for i = 2, #lines do
    local tokens = lines[i]:match "^#%s*detect:%s*(.-)%s*$"
    if tokens and #body == 0 then
      vim.list_extend(detect, vim.split(tokens, "%s+", { trimempty = true }))
    else
      body[#body + 1] = lines[i]
    end
  end
  while #body > 0 and body[#body] == "" do
    body[#body] = nil
  end
  while #body > 0 and body[1] == "" do
    table.remove(body, 1)
  end
  return {
    name = name,
    title = title or header:match "^#%s*(.-)%s*$",
    desc = desc ~= "" and desc or nil,
    header = header,
    detect = detect,
    body = body,
    path = path or name,
  }
end

--- Secrets first (the reason to have one), the editor and system leftovers last, the languages by name in between
---@param list IgnorePreset[]
---@return IgnorePreset[]
function M.order(list)
  local rank = { secrets = 0, base = 2 }
  table.sort(list, function(a, b)
    local ra, rb = rank[a.name] or 1, rank[b.name] or 1
    if ra ~= rb then
      return ra < rb
    end
    return a.name < b.name
  end)
  return list
end

--- Every preset in the folder
---@param dir string? tests point it at their own
---@return IgnorePreset[]
function M.list(dir)
  dir = dir or M.dir()
  local out = {}
  for file, kind in vim.fs.dir(dir) do
    if kind == "file" and file:match "%.gitignore$" then
      local path = dir .. "/" .. file
      local f = io.open(path, "r")
      if f then
        local text = f:read "*a"
        f:close()
        local preset = M.parse((file:gsub("%.gitignore$", "")), text, path)
        if preset then
          out[#out + 1] = preset
        end
      end
    end
  end
  return M.order(out)
end

return M
