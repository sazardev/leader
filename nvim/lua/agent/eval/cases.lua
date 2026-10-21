-- ── Eval cases ───────────────────────────────────────────────────────────────
-- A case is a folder under `evals/<action>/<name>/` at the repo root: a small project (the files next to `case.json`)
-- and the question put to the agent. Contract of `case.json`:
--
--   file         string    the file the agent works on (relative to the case folder)
--   lang         string    its filetype
--   line         integer   where the cursor is (the target is resolved from it, like in the editor)
--   input        string?   the instruction typed in the inline field (refactor, implement…)
--   diagnostics  { line, message, severity? }[]?   what the language server would say (seeded: no LSP in an eval)
--   check        table     what a good answer looks like (agent/eval/judge.lua), plus `cmd`: a command that must exit 0
--                          after the answer is applied, run in the case's temp project
--   split        string?   "dev" (default) or "holdout": prompts are tuned against dev, holdout is only measured
--   notes        string?   why the case exists (what a weak model gets wrong here)
--
-- Every case must be solvable and must be failable: `cassettes/<case>/golden.json` is a hand-written good answer
-- (it must pass) and the `noop` baseline (answer with nothing useful) must fail. The test suite checks both, so a case
-- cannot silently turn into one that everything passes, or nothing does.
local M = {}

---@class AgentEvalCase
---@field id string        "fix/py-undefined-name"
---@field action string
---@field dir string
---@field spec table
---@field split string

---@return string
function M.root()
  local here = debug.getinfo(1, "S").source:sub(2)
  -- the config is usually a symlink to the repo: resolve it, `evals/` sits next to `nvim/`, not next to the link
  here = vim.uv.fs_realpath(here) or here
  return vim.fn.fnamemodify(here, ":p:h:h:h:h:h") .. "/evals"
end

---@param root string?
---@return AgentEvalCase[]
function M.list(root)
  root = root or M.root()
  local cases = {}
  for _, path in ipairs(vim.fn.glob(root .. "/*/*/case.json", false, true)) do
    local dir = vim.fs.dirname(path)
    local ok, spec = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    end)
    if ok and type(spec) == "table" then
      local action = vim.fs.basename(vim.fs.dirname(dir))
      cases[#cases + 1] = {
        id = action .. "/" .. vim.fs.basename(dir),
        action = action,
        dir = dir,
        spec = spec,
        split = spec.split or "dev",
      }
    end
  end
  table.sort(cases, function(a, b)
    return a.id < b.id
  end)
  return cases
end

--- Cases whose id contains `filter` (a comma list: "fix,docs/py"), in the split asked for (nil = every split)
---@param cases AgentEvalCase[]
---@param filter string?
---@param split string?
---@return AgentEvalCase[]
function M.select(cases, filter, split)
  local words = {}
  for word in (filter or ""):gmatch "[^,%s]+" do
    words[#words + 1] = word
  end
  return vim.tbl_filter(function(case)
    if split and case.split ~= split then
      return false
    end
    if #words == 0 then
      return true
    end
    for _, word in ipairs(words) do
      if case.id:find(word, 1, true) then
        return true
      end
    end
    return false
  end, cases)
end

--- What is wrong with a case's declaration ("" = nothing): a typo in a key would turn a check off in silence
---@param case AgentEvalCase
---@return string[] problems
function M.problems(case)
  local out, s = {}, case.spec
  for _, key in ipairs { "file", "lang", "line" } do
    if s[key] == nil then
      out[#out + 1] = "missing `" .. key .. "`"
    end
  end
  if type(s.check) ~= "table" then
    out[#out + 1] = "missing `check`"
  else
    local known = {
      outside = 1,
      contains = 1,
      absent = 1,
      preserves = 1,
      findings = 1,
      max_findings = 1,
      cmd = 1,
      changes = 1,
    }
    for key in pairs(s.check) do
      if not known[key] then
        out[#out + 1] = "unknown check `" .. key .. "`"
      end
    end
  end
  if s.file and vim.fn.filereadable(case.dir .. "/" .. s.file) == 0 then
    out[#out + 1] = "file `" .. s.file .. "` does not exist"
  end
  if case.split ~= "dev" and case.split ~= "holdout" then
    out[#out + 1] = "split must be dev or holdout"
  end
  return out
end

return M
