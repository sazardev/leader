-- ── Test gaps (local, 0 tokens) ──────────────────────────────────────────────
-- Which public functions in this folder do not appear in any test file? Read via treesitter and text:
-- a "covered" function is one that some test file names (`TestParse`, `test_parse`, `parse(`...). It is an
-- approximate map (a short name can give a false "covered"), but free and enough to decide where to
-- ask for tests with `<leader>aTw`. The result goes to the quickfix list.
local convention = require "agent.tests.convention"
local log = require "utils.log"
local scopes = require "agent.context.scopes"

local M = {}

local MAX_FILES = 60

---@param name string?
---@param lang string
---@return boolean
local function public(name, lang)
  if not name or name == "" then
    return false
  end
  if lang == "go" then
    return name:match "^%u" ~= nil
  end
  return not name:match "^_" and name ~= "constructor"
end

---@param path string
---@return string
local function slurp(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and table.concat(lines, "\n") or ""
end

function M.run()
  local buf = vim.api.nvim_get_current_buf()
  local abs = vim.api.nvim_buf_get_name(buf)
  local lang = vim.bo[buf].filetype
  if abs == "" or vim.bo[buf].buftype ~= "" then
    return log.warn "Agent: only works in file buffers"
  end
  if not convention.locate(abs, lang) then
    return log.warn(("Agent: no test convention for filetype `%s`"):format(lang))
  end

  local dir, ext = vim.fs.dirname(abs), abs:match "%.([^.]+)$"
  local sources, tests = {}, {}
  for name, kind in vim.fs.dir(dir) do
    local path = dir .. "/" .. name
    if kind == "file" and name:match("%." .. ext .. "$") then
      if convention.is_test_file(path) then
        tests[#tests + 1] = path
      elseif #sources < MAX_FILES then
        sources[#sources + 1] = path
      end
    end
  end

  -- the convention's test files (e.g. tests/test_x.py, test/x_test.dart) and those of this folder
  local seen = {}
  for _, t in ipairs(tests) do
    seen[t] = true
  end
  for _, s in ipairs(sources) do
    local info = convention.locate(s, lang)
    if info and not info.inline and info.exists and not seen[info.path] then
      seen[info.path] = true
      tests[#tests + 1] = info.path
    end
  end
  local haystack = {}
  for _, t in ipairs(tests) do
    haystack[#haystack + 1] = slurp(t)
  end
  local text = table.concat(haystack, "\n")

  local items, total = {}, 0
  for _, path in ipairs(sources) do
    local src = slurp(path)
    local info = convention.locate(path, lang)
    -- Rust: the tests live in the file itself, in its #[cfg(test)] block
    local own = ""
    if info and info.inline then
      local at = src:find "#%[cfg%(test%)%]"
      own = at and src:sub(at) or ""
    end
    for _, f in ipairs(scopes.functions(src, lang)) do
      if public(f.name, lang) then
        total = total + 1
        if not text:find(f.name, 1, true) and not own:find(f.name, 1, true) then
          items[#items + 1] = {
            filename = path,
            lnum = f.first,
            text = ("%s: no test mentions it"):format(f.name),
          }
        end
      end
    end
  end

  if total == 0 then
    return log.info "Tests: no public functions found in this folder"
  end
  vim.fn.setqflist({}, " ", { title = ("Untested functions (%d of %d)"):format(#items, total), items = items })
  if #items == 0 then
    return log.info(("Tests: all %d public functions in this folder are mentioned by a test ✓"):format(total))
  end
  vim.cmd "copen"
  log.info(
    ("Tests: %d of %d public functions in this folder have no test (<leader>aTw writes one)"):format(#items, total)
  )
end

return M
