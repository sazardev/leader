-- ── Make: the one source of tasks ────────────────────────────────────────────
-- The task runner works with a Makefile and ONLY with a Makefile: no file, no tasks (`<leader>Rc` creates one from a
-- preset, `presets/`). Make cannot list its tasks, so two sources are put together. `make -qp` (prints the database, runs nothing, exit code 1
-- on purpose) tells what only make knows: the `.PHONY` targets after `include`s and variables, and the default goal. The
-- Makefile's own text gives the descriptions: `target: ## text` or a comment on the line right above the target. Without a
-- GNU make (Windows, BSD) the text alone is parsed. Pure parts: `parse_db`, `parse_file`, `build`.
local util = require "tasks.util"

---@class Task
---@field name string
---@field desc string?
---@field cmd string[]      argv; it runs in `cwd`
---@field cwd string
---@field default boolean?  what a bare `make` runs
---@field dry string[]?     argv that prints what the task would do without doing it

local M = {}

local FILES = { "GNUmakefile", "makefile", "Makefile" }

---@param dir string
---@param stop string?
---@return string?
function M.detect(dir, stop)
  return util.find_up(FILES, dir, stop)
end

--- The Makefile and the `*.mk` beside it (the usual includes): when one changes the cached list is stale
---@param file string
---@return string
function M.stamp(file)
  local paths = { file }
  vim.list_extend(paths, vim.fn.glob(vim.fs.dirname(file) .. "/*.mk", false, true))
  return util.stamp(paths)
end

--- What `make -qp` printed: the `.PHONY` targets and the default goal
---@param text string
---@return { phony: string[], default: string? }
function M.parse_db(text)
  local phony, seen, default = {}, {}, nil
  for line in text:gmatch "[^\n]+" do
    local list = line:match "^%.PHONY:%s*(.*)"
    if list then
      for name in list:gmatch "%S+" do
        if not seen[name] then
          seen[name] = true
          phony[#phony + 1] = name
        end
      end
    end
    default = default or line:match "^%.DEFAULT_GOAL := (%S+)"
  end
  return { phony = phony, default = default }
end

--- Rows of dashes or equal signs are section titles, not descriptions
---@param text string
---@return boolean
local function decoration(text)
  return text:match "^[%-=#*_%s]+$" ~= nil
end

--- What the Makefile's text says: its targets in order, which are `.PHONY`, their descriptions
---@param lines string[]
---@return { order: string[], phony: string[], desc: table<string, string> }
function M.parse_file(lines)
  local order, seen, phony, desc = {}, {}, {}, {}
  local comment
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local list = line:match "^%.PHONY%s*:%s*(.*)"
    if list then
      while list:sub(-1) == "\\" and lines[i + 1] do
        list = list:sub(1, -2) .. " " .. lines[i + 1]
        i = i + 1
      end
      for name in list:gmatch "%S+" do
        phony[#phony + 1] = name
      end
      comment = nil
    else
      local name, rest = line:match "^([%w_][%w_.%-]*)%s*:(.*)$"
      if name and not rest:match "^:?=" then
        if not seen[name] then
          seen[name] = true
          order[#order + 1] = name
        end
        local text = util.text(rest:match "##%s*(.-)%s*$") or comment
        if text then
          desc[name] = text
        end
        comment = nil
      else
        local c = line:match "^##?%s*(.+)$"
        comment = c and not decoration(c) and vim.trim(c) or nil
      end
    end
    i = i + 1
  end
  return { order = order, phony = phony, desc = desc }
end

---@param name string
---@return boolean
local function listable(name)
  return not name:match "^%." and not name:find "[%%/%$%s]"
end

--- The tasks: the `.PHONY` targets plus the described ones; with neither, every target in the file
---@param dir string
---@param db { phony: string[], default: string? }? nil without a GNU make
---@param src { order: string[], phony: string[], desc: table<string, string> }
---@return Task[]
function M.build(dir, db, src)
  local pos = {}
  for i, name in ipairs(src.order) do
    pos[name] = i
  end
  local names, seen = {}, {}
  local function add(name)
    if not seen[name] and listable(name) then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  for _, name in ipairs(db and #db.phony > 0 and db.phony or src.phony) do
    add(name)
  end
  for _, name in ipairs(src.order) do
    if src.desc[name] then
      add(name)
    end
  end
  if #names == 0 then
    for _, name in ipairs(src.order) do
      add(name)
    end
  end
  table.sort(names, function(a, b)
    local pa, pb = pos[a] or math.huge, pos[b] or math.huge
    if pa ~= pb then
      return pa < pb
    end
    return a < b
  end)
  local default = db and db.default or src.order[1]
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = {
      name = name,
      desc = src.desc[name],
      cmd = { "make", name },
      cwd = dir,
      default = name == default or nil,
      dry = { "make", "-n", name },
    }
  end
  return out
end

---@param file string
---@param cb fun(tasks: Task[])
function M.list(file, cb)
  local dir = vim.fs.dirname(file)
  local src = M.parse_file(util.lines(file))
  if vim.fn.executable "make" ~= 1 then
    return cb(M.build(dir, nil, src))
  end
  util.run({ "make", "-qp" }, { cwd = dir, env = { LC_ALL = "C" } }, function(res)
    -- only GNU make prints this database the way it is read here
    local db = res.stdout:find("GNU Make", 1, true) and M.parse_db(res.stdout) or nil
    cb(M.build(dir, db, src))
  end)
end

return M
