-- ── Go setup presets ─────────────────────────────────────────────────────────
-- `<leader>gS…` creates the config files a Go project usually wants. A preset is a plain file in `presets/<topic>/<variant>.<ext>`
-- (the extension is only for your editor: the variant is the name before it). Drop one in and it is discovered. Its shape:
--
--   # golangci-lint v2, strict: what it is, in one line     <- line 1: written to the file as its first comment
--   # target: .golangci.yml                                 <- line 2: where it goes, relative to the module root (not written)
--   …the file, with `{{module}}` `{{go}}` `{{main}}` `{{binary}}` filled in from the project (`vars.lua`)
--
-- Every variant of a topic goes to the same target. Every format that gets a preset takes `#` comments.
local M = {}

---@class SetupVariant
---@field name string
---@field desc string
---@field target string
---@field body string   the file as it will be written (placeholders not filled)
---@field path string

---@return string
function M.dir()
  return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
end

---@param name string
---@param text string
---@param path string?
---@return SetupVariant?
function M.parse(name, text, path)
  local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
  local desc = lines[1] and lines[1]:match "^#%s*(.-)%s*$"
  local target = lines[2] and lines[2]:match "^#%s*target:%s*(%S+)%s*$"
  if not desc or desc == "" or not target then
    return nil
  end
  local rest = { lines[1] }
  vim.list_extend(rest, lines, 3)
  return { name = name, desc = desc, target = target, body = table.concat(rest, "\n"), path = path or name }
end

--- The variants of a topic (a folder), by name
---@param folder string
---@param dir string? tests point it at their own
---@return SetupVariant[]
function M.variants(folder, dir)
  dir = (dir or M.dir()) .. "/" .. folder
  local out = {}
  for file, kind in vim.fs.dir(dir) do
    if kind == "file" then
      local f = io.open(dir .. "/" .. file, "r")
      if f then
        local text = f:read "*a"
        f:close()
        local variant = M.parse(file:match "^(.-)%.[^.]+$" or file, text, dir .. "/" .. file)
        if variant then
          out[#out + 1] = variant
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

return M
