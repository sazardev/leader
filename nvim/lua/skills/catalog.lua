-- ── Skills: marketplaces (search + install) ─────────────────────────────────
-- Three sources, all optional and best-effort (a marketplace down never breaks
-- the installed list):
--   1. skill.sh / `npx skills` CLI (skills.sh, vercel-labs/skills): `find` /
--      `add <repo> --skill <id> -a opencode [-g] -y` / `check` (needs Node 22+).
--   2. HTTP catalogs (opencode.json `skills` array): `<url>/index.json` →
--      `{ skills = { { name, version, files } } }` (OpenCode 2).
--   3. Curated offline list (skills/store.CURATED): always available, no net.
-- Install writes into the same dirs store.lua discovered; Leader never runs a
-- package manager without the user pressing install (same rule as sysdeps).
local store = require "skills.store"

local M = {}

--- HTTP catalogs to ask when `skills.sources` has none (settings override).
M.HTTP_CATALOGS = {
  "https://opencodeskills.dev/catalog/",
  "https://skills.sh/",
}

local function has_npx()
  return vim.fn.executable "npx" == 1 and vim.fn.executable "node" == 1
end

local function has_git()
  return vim.fn.executable "git" == 1
end

---@return { { id: string, kind: string, url?: string, repo?: string }[] }
function M.sources()
  local cfg = require("core.settings").skills
  if cfg.sources and #cfg.sources > 0 then
    return cfg.sources
  end
  local out = { { id = "skills.sh", kind = "skills_cli" }, { id = "curated", kind = "curated" } }
  for _, url in ipairs(M.HTTP_CATALOGS) do
    out[#out + 1] = { id = url:gsub("^https?://", ""):gsub("/$", ""), kind = "http", url = url }
  end
  return out
end

--- Filter the offline catalog by a query (name + desc + tags + langs).
---@param query string
---@return table[] entries
function M.curated_search(query)
  local needle = (query or ""):lower()
  if needle == "" then
    return store.CURATED
  end
  return vim.tbl_filter(function(e)
    local hay = (e.id .. " " .. e.desc .. " " .. (e.tags or "") .. " " .. table.concat(e.langs or {}, " ")):lower()
    return hay:find(needle, 1, true) ~= nil
  end, store.CURATED)
end

--- Search across marketplaces. Async: `cb(entries)` (may be called from a timer).
--- With `npx skills find` the live results win; without it the curated list answers.
---@param query string
---@param cb fun(entries: table[])
function M.search(query, cb)
  if has_npx() then
    local ok = pcall(vim.system, { "npx", "-y", "skills", "find", query or "" }, { text = true, timeout = 15000 }, function(out)
      vim.schedule(function()
        local live = {}
        if out.code == 0 and out.stdout then
          for id, desc in (out.stdout or ""):gmatch "([%w%-%_]+)[^\n]*%-+[%s]*([^\n]+)" do
            live[#live + 1] = { id = id, name = id, desc = desc, source = "skills.sh" }
          end
        end
        if #live > 0 then
          -- keep curated first for stable rows, live after
          cb(vim.list_extend(vim.deepcopy(M.curated_search(query)), live))
        else
          cb(M.curated_search(query))
        end
      end)
    end)
    if ok then
      return
    end
  end
  cb(M.curated_search(query))
end

--- Install one catalog entry. `cb(ok, detail)`.
--- Preferred: `npx skills add <repo> --skill <id> -a opencode -y` (global adds `-g`).
--- Fallback: shallow clone the repo to cache and copy the skill dir in.
---@param entry { id: string, repo?: string, source?: string }
---@param scope "project"|"global"?
---@param cb fun(ok: boolean, detail: string?)
function M.install(entry, scope, cb)
  scope = scope or require("core.settings").skills.scope or "project"
  if has_npx() and entry.repo then
    local cmd = { "npx", "-y", "skills", "add", entry.repo, "--skill", entry.id, "-a", "opencode", "-y" }
    if scope == "global" then
      cmd[#cmd + 1] = "-g"
    end
    local ok = pcall(vim.system, cmd, { text = true, timeout = 120000 }, function(out)
      vim.schedule(function()
        if out.code == 0 then
          cb(true, entry.id .. " installed via skills CLI")
        else
          cb(false, "skills CLI: " .. vim.trim((out.stderr or out.stdout or "failed"):sub(1, 200)))
        end
      end)
    end)
    if ok then
      return
    end
  end
  if not (has_git() and entry.repo) then
    return cb(false, "skills CLI not found and no repo to clone: run `npx skills add " .. (entry.repo or "?") .. " --skill " .. entry.id .. " -a opencode`")
  end
  local cache = vim.fn.stdpath "cache" .. "/skills/" .. entry.repo:gsub("/", "_")
  local function copy_in()
    local src = cache .. "/skills/" .. entry.id
    local src2 = cache .. "/" .. entry.id
    local base = scope == "global" and store.dirs("global")[1]
      or require("utils.project").git_root(require("utils.project").file_dir()) .. "/.agents/skills"
    local dst = base .. "/" .. entry.id
    vim.fn.mkdir(dst, "p")
    local file = vim.uv.fs_stat(src .. "/SKILL.md") and (src .. "/SKILL.md") or (vim.uv.fs_stat(src2 .. "/SKILL.md") and (src2 .. "/SKILL.md"))
    if not file then
      return cb(false, "repo cloned but skills/" .. entry.id .. "/SKILL.md not found")
    end
    local text = require("utils.project").read(file)
    local f = io.open(dst .. "/SKILL.md", "w")
    if not f then
      return cb(false, "cannot write " .. dst)
    end
    f:write(text)
    f:close()
    store.lock_add(entry.id, entry.repo, dst .. "/SKILL.md")
    cb(true, entry.id .. " installed (git fallback)")
  end
  local function clone()
    vim.system({ "git", "clone", "--depth", "1", "https://github.com/" .. entry.repo .. ".git", cache }, { text = true }, function(out)
      vim.schedule(function()
        if out.code == 0 then
          copy_in()
        else
          cb(false, "git clone: " .. vim.trim((out.stderr or ""):sub(1, 160)))
        end
      end)
    end)
  end
  if vim.uv.fs_stat(cache) then
    copy_in()
  else
    clone()
  end
end

--- Check for updates of installed skills (skills CLI only; offline it says so).
---@param cb fun(ok: boolean, text: string?)
function M.check_updates(cb)
  if not has_npx() then
    return cb(false, "skills CLI not found: install Node.js 22+ for `npx skills check`")
  end
  pcall(vim.system, { "npx", "-y", "skills", "check" }, { text = true, timeout = 30000 }, function(out)
    vim.schedule(function()
      cb(out.code == 0, vim.trim((out.stdout or out.stderr or ""):sub(1, 400)))
    end)
  end)
end

return M
