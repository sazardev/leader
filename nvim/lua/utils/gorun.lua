-- ── Go run/build target (file-based, tolerant to several mains) ──────────────
-- `gr` / `gb` run the package of the CURRENT file when that package can run
-- (a `main` package with `func main`), so each `main.go` variant of the repo
-- runs its own binary: root `main.go`, `cmd/api/main.go`, `cmd/worker/...`,
-- any other folder with a main. Otherwise (editing library code) it falls
-- back to the module's main: the only one, or the preferred `cmd/*` one.
-- No module (a lone file): `go run <file>` in its folder, as before.
local M = {}

local SKIP_DIRS = {
  [".git"] = true,
  [".hg"] = true,
  vendor = true,
  node_modules = true,
  testdata = true,
  [".idea"] = true,
  [".vscode"] = true,
  dist = true,
  build = true,
}

local PREFERRED = { "api", "server", "app", "service", "web", "main" }

---@param seg string
---@return boolean
local function skipped_rel(rel)
  for seg in rel:gmatch "[^/]+" do
    if SKIP_DIRS[seg] then
      return true
    end
  end
  return false
end

--- Package clause + `func main` of a source text (nil package when the file is
--- not part of the build). Pure.
---@param src string
---@return string? pkg, boolean has_main
function M.of_src(src)
  local head = src:sub(1, 8192)
  if head:find("//go:build ignore", 1, true) then
    return nil, false
  end
  local pkg, has_main = nil, false
  for line in (src .. "\n"):gmatch "([^\n]*)\n" do
    local stripped = line:match "^%s*(.-)%s*$"
    if not stripped:match "^//" then
      if not pkg then
        pkg = stripped:match "^package%s+([%w_]+)"
      end
      if stripped:match "^func%s+main%s*%(" then
        has_main = true
      end
    end
    if pkg and has_main then
      break
    end
  end
  return pkg, has_main
end

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

--- Is `dir` a runnable package (some non-test file says `package main` and
--- some (maybe another) defines `func main`)? `live` replaces its file on
--- disk with the unsaved buffer. Files with `//go:build ignore` don't count.
---@param dir string
---@param live { path: string, text: string }?
---@return boolean
function M.dir_is_main(dir, live)
  local pkg_main, func_main = false, false
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match "%.go$" and not name:match "_test%.go$" then
      local path = dir .. "/" .. name
      local src
      if live and live.path == path then
        src = live.text
      else
        src = read(path)
      end
      if src then
        local pkg, main = M.of_src(src)
        if pkg == "main" then
          pkg_main = true
          -- `func main` in a non-main package is just a function called
          -- main, not an entry point: it only counts inside `package main`.
          if main then
            func_main = true
          end
        end
      end
    end
    if pkg_main and func_main then
      return true
    end
  end
  return pkg_main and func_main
end

--- `.` for the module root, else `./rel/path` (forward slashes). Pure.
---@param root string
---@param dir string
---@return string
function M.rel_pkg(root, dir)
  if dir == root then
    return "."
  end
  local rel = dir:sub(#root + 2):gsub("\\", "/")
  return "./" .. rel
end

--- Absolute dirs under `root` holding a verified main package, sorted.
--- Phase 1: folders with a `main.go` (the usual variants). Phase 2 (only when
--- phase 1 finds nothing): any folder with a main package (a `server.go` with
--- `func main` and no `main.go`).
---@param root string
---@return string[]
function M.list_mains(root)
  local with_main_go = {}
  local any_go_dirs = {}
  local count = 0
  for rel, kind in vim.fs.dir(root, { depth = 6 }) do
    if kind == "file" and rel:match "%.go$" and not rel:match "_test%.go$" and not skipped_rel(rel) then
      count = count + 1
      if count > 4000 then
        break
      end
      local dir = vim.fs.dirname(rel)
      local abs = dir == "." and root or (root .. "/" .. dir)
      any_go_dirs[abs] = true
      if vim.fs.basename(rel) == "main.go" then
        with_main_go[abs] = true
      end
    end
  end
  local out = {}
  for dir in pairs(with_main_go) do
    if M.dir_is_main(dir) then
      out[#out + 1] = dir
    end
  end
  if #out == 0 then
    for dir in pairs(any_go_dirs) do
      if M.dir_is_main(dir) then
        out[#out + 1] = dir
      end
    end
  end
  table.sort(out)
  return out
end

--- Which of `mains` (absolute, sorted) to run when the current file is not in
--- a main package: the root when it is one, else the preferred `cmd/*`, else
--- the first. Pure over relative paths.
---@param mains string[] absolute dirs
---@param root string
---@return string?
function M.preferred(mains, root)
  if #mains == 0 then
    return nil
  end
  local rels = vim.tbl_map(function(d)
    return M.rel_pkg(root, d)
  end, mains)
  for _, r in ipairs(rels) do
    if r == "." then
      return root
    end
  end
  local by_cmd = {}
  for i, r in ipairs(rels) do
    local name = r:match "^%./cmd/([^/]+)$" or r:match "^%./cmd/([^/]+)/"
    if name then
      by_cmd[name] = by_cmd[name] or mains[i]
    end
  end
  for _, name in ipairs(PREFERRED) do
    if by_cmd[name] then
      return by_cmd[name]
    end
  end
  local cmds = vim.tbl_keys(by_cmd)
  if #cmds > 0 then
    table.sort(cmds)
    return by_cmd[cmds[1]]
  end
  return mains[1]
end

---@class GoRunTarget
---@field pkg string  `.` | `./cmd/api` | file name (no module)
---@field cwd string  where to run it (the module root, or the file's folder)
---@field mode string `file`|`file-main`|`ancestor-main`|`only-main`|`preferred-main`
---@field note string? why this package (shown when it is not the file's own)

--- Resolve what `go run` / `go build` should run for `file`.
---@param file string? defaults to the current buffer
---@param buf_text string? unsaved text of `file` (current buffer)
---@return GoRunTarget?, string? err
function M.resolve(file, buf_text)
  local path = file and file ~= "" and file or vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil, "Go: no file to run"
  end
  local dir = vim.fs.dirname(path)
  local gomod = vim.fs.find("go.mod", { path = dir, upward = true })[1]
  if not gomod then
    return { pkg = vim.fs.basename(path), cwd = dir, mode = "file" }, nil
  end
  local root = vim.fs.dirname(gomod)
  local live = { path = path, text = buf_text or read(path) or "" }

  if M.dir_is_main(dir, live) then
    return { pkg = M.rel_pkg(root, dir), cwd = root, mode = "file-main" }, nil
  end

  -- a library file nested under a main folder (cmd/api/routes/… → cmd/api)
  local cur = vim.fs.dirname(dir)
  while cur and #cur >= #root and cur:sub(1, #root) == root do
    if M.dir_is_main(cur) then
      return {
        pkg = M.rel_pkg(root, cur),
        cwd = root,
        mode = "ancestor-main",
        note = ("not a main package; running %s"):format(M.rel_pkg(root, cur)),
      }, nil
    end
    if cur == root then
      break
    end
    local parent = vim.fs.dirname(cur)
    if parent == cur then
      break
    end
    cur = parent
  end

  local mains = M.list_mains(root)
  if #mains == 0 then
    return nil, "Go: no main package found (the current file is not in a main package)"
  end
  if #mains == 1 then
    return {
      pkg = M.rel_pkg(root, mains[1]),
      cwd = root,
      mode = "only-main",
      note = ("not a main package; running %s"):format(M.rel_pkg(root, mains[1])),
    }, nil
  end
  local pick = M.preferred(mains, root) or mains[1]
  return {
    pkg = M.rel_pkg(root, pick),
    cwd = root,
    mode = "preferred-main",
    note = ("not a main package; running %s (%d mains)"):format(M.rel_pkg(root, pick), #mains),
  }, nil
end

return M
