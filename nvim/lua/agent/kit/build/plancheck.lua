-- ── Build with agent: is the plan buildable? (pure, 0 tokens) ────────────────
-- A plan is written in one go, and its mistakes cost the most when they are found last: a Go package cycle (`ui` owns
-- the screen, the screen uses `ui`'s styles) is written faithfully file by file and only `go build` says it, when the
-- fix is moving files between packages, which a fix round on one file cannot do. Here, before the review: the files are
-- put in an order where every file comes after the files it uses (the model's `needs` are kept, never dropped: a file
-- written without seeing what it uses invents its API), and what cannot be built as planned is named: a file that needs
-- one the plan does not have, files that need each other, Go packages that import each other. The build asks for a new
-- plan once with those problems, and shows what is left.
local M = {}

---@param path string
---@return boolean
local function is_go(path)
  return path:match "%.go$" ~= nil
end

--- The Go package of a file: its directory
---@param path string
---@return string
local function package(path)
  local dir = vim.fs.dirname(path)
  return dir == "" and "." or dir
end

--- The files in an order where every file comes after the ones it needs, as close to the plan's order as that allows
--- (stable: among the files ready to go, the one the plan listed first). Files on a cycle keep their place at the end.
---@param files BuildFile[]
---@return BuildFile[] ordered, string[][] cycles (each a list of paths)
function M.order(files)
  local index, by_path = {}, {}
  for i, f in ipairs(files) do
    index[f.path], by_path[f.path] = i, f
  end
  local pending = {} -- how many needs each file still waits for
  local users = {} -- path → files that need it
  for _, f in ipairs(files) do
    pending[f.path] = 0
    for _, n in ipairs(f.needs or {}) do
      if by_path[n] and n ~= f.path then
        pending[f.path] = pending[f.path] + 1
        users[n] = users[n] or {}
        table.insert(users[n], f.path)
      end
    end
  end
  local out, done = {}, {}
  while true do
    local pick
    for _, f in ipairs(files) do
      if not done[f.path] and pending[f.path] == 0 and (not pick or index[f.path] < index[pick]) then
        pick = f.path
      end
    end
    if not pick then
      break
    end
    done[pick] = true
    out[#out + 1] = by_path[pick]
    for _, u in ipairs(users[pick] or {}) do
      pending[u] = pending[u] - 1
    end
  end
  local left = {}
  for _, f in ipairs(files) do
    if not done[f.path] then
      out[#out + 1] = f
      left[f.path] = true
    end
  end
  local cycles = next(left) and M.cycles(files, function(f)
    return left[f.path] and f.path or nil
  end) or {}
  return out, cycles
end

--- The cycles of a graph whose nodes are what `node(file)` returns (a path, a package; nil = not in the graph), its
--- edges the files' needs (pure; each cycle once, as the list of its nodes)
---@param files BuildFile[]
---@param node fun(f: BuildFile): string?
---@return string[][]
function M.cycles(files, node)
  local by_path, edges = {}, {}
  for _, f in ipairs(files) do
    by_path[f.path] = f
  end
  for _, f in ipairs(files) do
    local from = node(f)
    if from then
      edges[from] = edges[from] or {}
      for _, n in ipairs(f.needs or {}) do
        local to = by_path[n] and node(by_path[n])
        if to and to ~= from and not vim.tbl_contains(edges[from], to) then
          table.insert(edges[from], to)
        end
      end
    end
  end
  local nodes = vim.tbl_keys(edges)
  table.sort(nodes)
  local out, seen_cycle = {}, {}
  local state = {} -- nil = new, 1 = on the stack, 2 = done
  local stack = {}
  local function visit(v)
    state[v] = 1
    stack[#stack + 1] = v
    local nexts = vim.deepcopy(edges[v] or {})
    table.sort(nexts)
    for _, w in ipairs(nexts) do
      if state[w] == 1 then -- back to a node on the stack: the cycle is the stack from it
        local cycle, on = {}, false
        for _, s in ipairs(stack) do
          on = on or s == w
          if on then
            cycle[#cycle + 1] = s
          end
        end
        local key = table.concat(vim.fn.sort(vim.deepcopy(cycle)), "|")
        if not seen_cycle[key] then
          seen_cycle[key] = true
          out[#out + 1] = cycle
        end
      elseif not state[w] then
        visit(w)
      end
    end
    stack[#stack] = nil
    state[v] = 2
  end
  for _, v in ipairs(nodes) do
    if not state[v] then
      visit(v)
    end
  end
  return out
end

--- Which files make package `from` import package `to` (for the message: what to move)
---@param files BuildFile[]
---@param from string
---@param to string
---@return string[]
local function importers(files, from, to)
  local by_path, out = {}, {}
  for _, f in ipairs(files) do
    by_path[f.path] = f
  end
  for _, f in ipairs(files) do
    if is_go(f.path) and package(f.path) == from then
      for _, n in ipairs(f.needs or {}) do
        if by_path[n] and is_go(n) and package(n) == to then
          out[#out + 1] = ("%s uses %s"):format(f.path, n)
        end
      end
    end
  end
  return out
end

--- What cannot be built as planned, one sentence each with what to change (pure)
---@param plan BuildPlan
---@param missing string[]? needs the plan does not have ("a.go needs b.go"), from parse
---@return string[]
function M.problems(plan, missing)
  local out = {}
  for _, m in ipairs(missing or {}) do
    out[#out + 1] = m .. ": add that file to the plan, or remove it from `needs`"
  end
  local _, file_cycles = M.order(plan.files)
  for _, c in ipairs(file_cycles) do
    local same_package = true -- Go files of one package may use each other: only the order is affected
    for _, p in ipairs(c) do
      same_package = same_package and is_go(p) and package(p) == package(c[1])
    end
    out[#out + 1] = not same_package
        and ("files that need each other: %s → %s. One of them must not need the other: move what both use into a third file"):format(
          table.concat(c, " → "),
          c[1]
        )
      or nil
  end
  local go_cycles = M.cycles(plan.files, function(f)
    return is_go(f.path) and package(f.path) or nil
  end)
  for _, c in ipairs(go_cycles) do
    local why = {}
    for i, from in ipairs(c) do
      local to = c[i % #c + 1]
      vim.list_extend(why, vim.list_slice(importers(plan.files, from, to), 1, 2))
    end
    out[#out + 1] = ("Go packages that import each other (Go refuses import cycles): %s → %s (%s). Move what they share (styles, keys, messages, types) into a package of its own that both import, and keep the dependency one way"):format(
      table.concat(c, " → "),
      c[1],
      table.concat(why, "; ")
    )
  end
  return out
end

--- Words that say a file stands in for something real
local STAND_IN =
  { "placeholder", "stub", "mock", "fake", "dummy", "sample data", "sample-data", "for now", "temporary", "todo" }

---@param text string
---@return boolean
local function stands_in(text)
  local low = text:lower()
  for _, w in ipairs(STAND_IN) do
    if low:find(w, 1, true) then
      return true
    end
  end
  return false
end

--- What is wrong with a plan that is not a reason to ask for another one (pure): shown in the review, where the user decides.
--- A build that is judged (the whole project, a feature, a recipe) must deliver SPEC.md: every requirement is built (a file
--- verifies it or a wiring row reaches it) or DEFERRED with what is missing, never dropped and never a silent stand-in
---@param plan BuildPlan
---@param spec string SPEC.md
---@param scope string?
---@return string[]
function M.warnings(plan, spec, scope)
  local out = {}
  local proof = require "agent.kit.build.proof"
  if proof.kind(scope) ~= "judged" then
    return out
  end
  local reqs = require("agent.kit.coverage").requirements(spec or "")
  local core = proof.core_ids(spec or "")
  local handled, deferred = {}, {}
  for _, f in ipairs(plan.files) do
    for id in (f.verifies or ""):gmatch "FR%-%d+" do
      handled[id] = true
    end
  end
  for _, w in ipairs(plan.wiring or {}) do
    handled[w.req] = true
  end
  for _, d in ipairs(plan.deferred or {}) do
    deferred[d.req] = d.why
    out[#out + 1] = ("%s is deferred: %s"):format(d.req, d.why)
  end
  local dropped = {}
  for _, r in ipairs(reqs) do
    if not handled[r.id] and not deferred[r.id] and (next(core) == nil or core[r.id]) then
      dropped[#dropped + 1] = r.id
    end
  end
  if #dropped > 0 then
    out[#out + 1] = ("%s: not built, not wired and not deferred by this plan"):format(table.concat(dropped, ", "))
  end
  for _, f in ipairs(plan.files) do
    if stands_in(f.purpose or "") then
      local ids = {}
      for id in ((f.verifies or "") .. " " .. (f.purpose or "")):gmatch "FR%-%d+" do
        if core[id] and not vim.tbl_contains(ids, id) then
          ids[#ids + 1] = id
        end
      end
      out[#out + 1] = ("%s is a stand-in (%s)%s"):format(
        f.path,
        (f.purpose or ""):sub(1, 70),
        #ids > 0 and (" for the core requirement " .. table.concat(ids, ", ")) or ""
      )
    end
  end
  if #(plan.risks or {}) == 0 and #reqs > 0 then
    out[#out + 1] = "the plan names no risky requirement, so nothing says the hard part is built first"
  end
  return out
end

return M
