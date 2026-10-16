-- ── Go: which `package` to suggest (no LLM, 0 tokens) ────────────────────────
-- gopls offers `package <dir>`, `package <dir>_test` and ALWAYS `package main`, and blink ranks `main` first by a hair. Here the
-- candidates are judged by where the file is:
--   · the other .go files of the folder decide: they say `package notes` → `notes` first and no `main`; they say `main` → `main` first
--   · no neighbours: `main` first only in `cmd/…`, in a file called `main.go`, or in the module root; anywhere else it is not
--     offered at all (typing `package m…` still brings it, because then you are asking for it)
--   · `X_test` stays below `X`, except in a `_test.go` file, where both are real options
-- It works on what gopls returned (`rank`), so a folder name gopls guesses badly still comes out as gopls spelled it.
local M = {}

---@class GoPackageInfo
---@field siblings string[]  packages of the other .go files in the folder (`_test` stripped)
---@field file string        the current file's name
---@field cmd boolean        the folder is under a `cmd` directory
---@field root boolean       the folder is the module root

---@class GoPackageDecision
---@field prefer string?  the package that goes first
---@field main boolean    `package main` may be listed

--- Decides from where the file is
---@param info GoPackageInfo
---@return GoPackageDecision
function M.decide(info)
  if #info.siblings > 0 then
    local count, best = {}, nil
    for _, name in ipairs(info.siblings) do
      count[name] = (count[name] or 0) + 1
      if not best or count[name] > count[best] or (count[name] == count[best] and name < best) then
        best = name
      end
    end
    return { prefer = best, main = best == "main" }
  end
  if info.file == "main.go" or info.cmd or info.root then
    return { prefer = "main", main = true }
  end
  return { prefer = nil, main = false }
end

---@param items table[]  completion items, as the LSP gave them
---@param typed string   what follows `package ` on the line
---@param decision GoPackageDecision
---@param test_file boolean the current file is `*_test.go`
---@return table[]
function M.rank(items, typed, decision, test_file)
  local out = {}
  for _, item in ipairs(items) do
    local name = type(item.label) == "string" and item.label:match "^package%s+([%w_]+)$"
    if not name then
      out[#out + 1] = item
    elseif name == "main" and not decision.main and typed:sub(1, 1):lower() ~= "m" then
      -- not offered here (unless it is being typed)
      goto continue
    else
      local offset
      if name == decision.prefer then
        offset = 20
      elseif decision.prefer and name == decision.prefer .. "_test" then
        offset = test_file and 10 or 0
      elseif name == "main" then
        offset = -5
      elseif name:match "_test$" then
        offset = test_file and 5 or 0
      else
        offset = decision.prefer and 0 or 5 -- no neighbours: the folder's own name before its `_test`
      end
      item.score_offset = (item.score_offset or 0) + offset
      out[#out + 1] = item
    end
    ::continue::
  end
  return out
end

--- The package clause of a file: its first `package x` line, `nil` for a file that is not part of the build (`go:build ignore`)
---@param path string
---@return string?
local function package_of(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local head = f:read(4096) or ""
  f:close()
  if head:find("//go:build ignore", 1, true) or head:find("// +build ignore", 1, true) then
    return nil
  end
  local in_block = false
  for line in head:gmatch "[^\n]*" do
    if in_block then
      in_block = not line:find("*/", 1, true)
    elseif line:match "^%s*/%*" then
      in_block = not line:find("*/", 1, true)
    else
      local name = line:match "^package%s+([%w_]+)"
      if name then
        return name
      end
    end
  end
end

--- What the folder of `path` says
---@param path string
---@return GoPackageInfo
function M.info(path)
  local dir = vim.fs.dirname(path)
  local siblings = {}
  for name, kind in vim.fs.dir(dir) do
    local full = dir .. "/" .. name
    if kind == "file" and name:match "%.go$" and full ~= path then
      local pkg = package_of(full)
      if pkg then
        siblings[#siblings + 1] = (pkg:gsub("_test$", ""))
      end
    end
  end
  local gomod = vim.fs.find("go.mod", { path = dir, upward = true })[1]
  local root = gomod and vim.fs.dirname(gomod)
  local rel = root and dir:sub(#root + 2) or dir
  local cmd = false
  for seg in rel:gmatch "[^/\\]+" do
    cmd = cmd or seg == "cmd"
  end
  return { siblings = siblings, file = vim.fs.basename(path), cmd = cmd, root = root == dir }
end

--- For the LSP's items at `package …`: the ones that make sense here, in the right order
---@param ctx { line: string, cursor: integer[] }
---@param items table[]
---@return table[]
function M.transform(ctx, items)
  local typed = ctx.line:sub(1, ctx.cursor[2]):match "^package%s+([%w_]*)$"
    or ctx.line:sub(1, ctx.cursor[2]):match "^p[%a]*$" and ""
    or nil
  if not typed then
    return items
  end
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return items
  end
  return M.rank(items, typed, M.decide(M.info(path)), path:match "_test%.go$" ~= nil)
end

return M
