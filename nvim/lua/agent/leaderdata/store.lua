-- ── The .leader/ folder of a project (disk) ──────────────────────────────────
-- Everything Leader records about how it worked on THIS project lives in `<project>/.leader/`, nowhere else, and never leaves
-- the machine: nothing in Leader sends it anywhere (there is no network code in this folder's modules, and a test checks it).
--
--   README.md      what is recorded, what never is, how to read it and how to delete it (generated from agent/leaderdata/schema.lua)
--   events.jsonl   one line per event: a build that ended, an agent action that ran, a decision about its proposal
--   salt           random; what turns a file path into a hash nobody can read back. Stays here, never in a report
--   .gitignore     `*`: the folder is never committed by accident
--
-- The file is capped (`settings.agent.leader_data.max_kb`): past it, the oldest half goes. Deleting the folder deletes it all.
local schema = require "agent.leaderdata.schema"

local M = {}

M.DIR = ".leader"

---@param root string
---@return string
function M.dir(root)
  return root .. "/" .. M.DIR
end

---@param root string
---@return boolean
function M.exists(root)
  local stat = vim.uv.fs_stat(M.dir(root))
  return stat ~= nil and stat.type == "directory"
end

---@return string
local function readme()
  local lines = {
    "# .leader",
    "",
    "Leader (the editor) keeps this folder about how it worked on this project, so it can be measured and improved from real use.",
    "It is read by you, on this machine. **Nothing here is ever sent anywhere**: Leader has no code that uploads it.",
    "",
    "## What is recorded",
    "",
    "Counts, sizes, durations, costs, models and outcomes: how a build ended, which checks failed, what a model cost, whether you accepted",
    "a proposal. File names become a salted hash, lengths become a bucket (`<50`, `<200`, `<500`, `500+`), project scripts become `custom`.",
    "The fields, per kind of event (this list is the schema the code enforces; anything else is dropped before it is written):",
    "",
  }
  vim.list_extend(lines, schema.describe())
  vim.list_extend(lines, {
    "",
    "## What is never recorded",
    "",
    "Your code, your documents (SPEC.md, STACK.md, DESIGN.md), prompts, what the model answered, file or folder names, function or type",
    "names, error or diagnostic text, instructions you typed, your environment variables, your name or machine.",
    "",
    "## Files",
    "",
    "- `events.jsonl`: one JSON object per line. `jq -s 'group_by(.kind)' events.jsonl` is a fine way in.",
    "- `salt`: random. It makes the hashes useless outside this folder. **Do not share it**; `events.jsonl` alone is safe to share.",
    "- `.gitignore`: ignores everything here, so it is never committed by accident.",
    "",
    "## Read it, switch it off, delete it",
    "",
    "- `<leader>aSl` in Neovim shows the report: builds, outcomes, costs, what fails.",
    "- Off: `settings.agent.leader_data.enabled = false` (or `LEADER_NO_DATA=1`). Leader then never creates or writes this folder.",
    "- Delete: remove this folder. Nothing else depends on it.",
    "",
  })
  return table.concat(lines, "\n")
end

--- Creates the folder and its fixed files when they are not there (README refreshed when the schema changed)
---@param root string
---@return string? dir, string? salt
function M.ensure(root)
  local dir = M.dir(root)
  vim.fn.mkdir(dir, "p")
  local function write(name, text)
    local f = io.open(dir .. "/" .. name, "w")
    if f then
      f:write(text)
      f:close()
    end
  end
  local function read(name)
    local f = io.open(dir .. "/" .. name, "r")
    if not f then
      return nil
    end
    local text = f:read "*a"
    f:close()
    return text
  end
  if not read ".gitignore" then
    write(".gitignore", "*\n")
  end
  local text = readme()
  if read "README.md" ~= text then
    write("README.md", text)
  end
  local salt = read "salt"
  if not salt or #salt < 16 then
    salt = vim.fn.sha256(tostring(vim.uv.hrtime()) .. tostring(math.random()) .. root):sub(1, 32)
    write("salt", salt)
  end
  return dir, vim.trim(salt)
end

---@return table settings.agent.leader_data
function M.settings()
  return require("core.settings").agent.leader_data or {}
end

---@return boolean
function M.enabled()
  return M.settings().enabled ~= false and (vim.env.LEADER_NO_DATA or "") == ""
end

--- Appends one event (already sanitized). Trims the file when it is past the cap
---@param root string
---@param event table
---@return boolean
function M.append(root, event)
  local dir = M.ensure(root)
  if not dir then
    return false
  end
  local path = dir .. "/events.jsonl"
  local f = io.open(path, "a")
  if not f then
    return false
  end
  f:write(vim.json.encode(event), "\n")
  f:close()
  local cap = (M.settings().max_kb or 2048) * 1024
  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > cap then
    local lines = vim.fn.readfile(path)
    vim.fn.writefile(vim.list_slice(lines, math.floor(#lines / 2) + 1), path)
  end
  return true
end

--- Every event in the folder, oldest first
---@param root string
---@return table[]
function M.read(root)
  local path = M.dir(root) .. "/events.jsonl"
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local out = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    local ok, event = pcall(vim.json.decode, line)
    if ok and type(event) == "table" then
      out[#out + 1] = event
    end
  end
  return out
end

return M
