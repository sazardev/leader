-- ── CHANGELOG.md from Conventional Commits (pure) ────────────────────────────
-- The commits since the last tag, grouped the way readers look for them (breaking changes first, then features, fixes,
-- performance, the rest), the next version from them (semver: a breaking change bumps the major, or the minor before
-- 1.0; a feature the minor; anything else the patch) and the section written at the top of CHANGELOG.md (a section of
-- the same version is replaced, never duplicated). Release commits (`chore(release): …`) and merges are left out.
-- Tested in test-release.lua.
local M = {}

---@class ReleaseCommit
---@field hash string
---@field type string     "feat", "fix"… ("other" when the subject is not conventional)
---@field scope string?
---@field breaking boolean
---@field subject string

--- The commits of `git log --format=%h%x1f%s%x1f%b%x1e`
---@param log string
---@return ReleaseCommit[]
function M.parse(log)
  local split = require("commit.conventional").split
  local out = {}
  for record in (log or ""):gmatch "([^\30]+)" do
    local hash, subject, body = record:match "^%s*([^\31]*)\31([^\31]*)\31?(.*)$"
    if hash and subject and subject ~= "" and not subject:match "^Merge " then
      local h = split(subject)
      local breaking = (h and h.breaking) or (body or ""):find("BREAKING CHANGE", 1, true) ~= nil
      if not (h and h.type == "chore" and h.scope == "release") then
        out[#out + 1] = {
          hash = vim.trim(hash),
          type = h and h.type or "other",
          scope = h and h.scope or nil,
          breaking = breaking and true or false,
          subject = h and h.subject or subject,
        }
      end
    end
  end
  return out
end

--- "v1.4.2" / "1.4.2+3" → 1, 4, 2 (nil when it is not a version)
---@param version string?
---@return integer?, integer?, integer?
function M.semver(version)
  local a, b, c = (version or ""):match "^v?(%d+)%.(%d+)%.(%d+)"
  if not a then
    return nil
  end
  return tonumber(a), tonumber(b), tonumber(c)
end

--- The version after `current` for these commits; nil when there is nothing to release
---@param current string? "1.4.2" (nil or unreadable = the first release, 0.1.0)
---@param commits ReleaseCommit[]
---@return string?, "major"|"minor"|"patch"|nil
function M.bump(current, commits)
  if #commits == 0 then
    return nil
  end
  local major, minor, patch = M.semver(current)
  if not major then
    return "0.1.0", "minor"
  end
  local breaking = vim.iter(commits):any(function(c)
    return c.breaking
  end)
  local feat = vim.iter(commits):any(function(c)
    return c.type == "feat"
  end)
  if breaking and major >= 1 then
    return ("%d.0.0"):format(major + 1), "major"
  elseif breaking or feat then
    return ("%d.%d.0"):format(major, minor + 1), "minor"
  end
  return ("%d.%d.%d"):format(major, minor, patch + 1), "patch"
end

M.GROUPS = {
  {
    title = "Breaking changes",
    match = function(c)
      return c.breaking
    end,
  },
  {
    title = "Features",
    match = function(c)
      return c.type == "feat"
    end,
  },
  {
    title = "Fixes",
    match = function(c)
      return c.type == "fix"
    end,
  },
  {
    title = "Performance",
    match = function(c)
      return c.type == "perf"
    end,
  },
  {
    title = "Other changes",
    match = function()
      return true
    end,
  },
}

--- The section of one version (pure): `## [1.5.0] - 2026-10-19` and its groups; each commit in the first group it fits
---@param version string
---@param date string
---@param commits ReleaseCommit[]
---@return string
function M.section(version, date, commits)
  local out = { ("## [%s] - %s"):format(version, date) }
  local used = {}
  for _, g in ipairs(M.GROUPS) do
    local rows = {}
    for i, c in ipairs(commits) do
      if not used[i] and g.match(c) then
        used[i] = true
        local scope = c.scope and ("**" .. c.scope .. ":** ") or ""
        local kind = (g.title == "Other changes" and c.type ~= "other") and (c.type .. ": ") or ""
        rows[#rows + 1] = ("- %s%s%s (%s)"):format(kind, scope, c.subject, c.hash)
      end
    end
    if #rows > 0 then
      vim.list_extend(out, { "", "### " .. g.title, "" })
      vim.list_extend(out, rows)
    end
  end
  return table.concat(out, "\n") .. "\n"
end

M.HEADER = "# Changelog\n\nAll notable changes, newest first. Generated from the Conventional Commits since each tag.\n"

--- CHANGELOG.md with the section at the top (pure): under the title and its intro; a section of the same version is
--- replaced
---@param text string? the file as it is (nil: a new one)
---@param version string
---@param section string
---@return string
function M.insert(text, version, section)
  text = text and text ~= "" and text or M.HEADER
  local lines = vim.split((text:gsub("\n+$", "")), "\n", { plain = true })
  local head = "## [" .. version .. "]"
  -- drop the old section of this version
  local from
  for i, l in ipairs(lines) do
    if l:sub(1, #head) == head then
      from = i
      break
    end
  end
  if from then
    local to = #lines
    for j = from + 1, #lines do
      if lines[j]:match "^## " then
        to = j - 1
        break
      end
    end
    for _ = from, to do
      table.remove(lines, from)
    end
  end
  local at = #lines + 1
  for i, l in ipairs(lines) do
    if l:match "^## " then
      at = i
      break
    end
  end
  while at > 1 and lines[at - 1] == "" do
    at = at - 1
  end
  local block = vim.split(vim.trim(section), "\n", { plain = true })
  table.insert(block, 1, "")
  if at <= #lines then
    block[#block + 1] = ""
  end
  for k = #block, 1, -1 do
    table.insert(lines, at, block[k])
  end
  return table.concat(lines, "\n"):gsub("\n\n\n+", "\n\n") .. "\n"
end

--- The project's version and where it is written (pure): VERSION, package.json, pubspec.yaml, Cargo.toml, pyproject.toml
---@param files table<string, string> name → text
---@return string? version, string? file
function M.current(files)
  local function found(file, v)
    return v and M.semver(v) and v or nil, v and file or nil
  end
  if files.VERSION then
    return found("VERSION", vim.trim(files.VERSION))
  end
  local reads = {
    { "package.json", '"version"%s*:%s*"([^"]+)"' },
    { "pubspec.yaml", "\nversion:%s*([%w%.%-+]+)" },
    { "Cargo.toml", '%[package%][^%[]-\nversion%s*=%s*"([^"]+)"' },
    { "pyproject.toml", '\nversion%s*=%s*"([^"]+)"' },
  }
  for _, r in ipairs(reads) do
    local text = files[r[1]]
    local v = text and ("\n" .. text):match(r[2])
    if v then
      return found(r[1], v)
    end
  end
  return nil
end

return M
