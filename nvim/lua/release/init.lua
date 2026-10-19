-- ── Release kit (<leader>GR): changelog, PR description, checklist ───────────
--   c  changelog   the commits since the last tag → the next version and its CHANGELOG.md section (0 tokens; asks first)
--   p  PR          the branch against its base → a pull request description (one light-tier request), in a buffer and
--                  the clipboard; nothing is ever posted
--   l  checklist   what must be true before releasing, checked where it can be (0 tokens): changelog.lua, checklist.lua
-- Never tags, pushes or publishes: those lines are shown for you to run. Knobs in `settings.git.release`.
local changelog = require "release.changelog"
local git = require "commit.git"
local log = require "utils.log"

local M = {}

---@return table
local function cfg()
  return require("core.settings").git.release or {}
end

---@param args string[]
---@param root string
---@return string
local function out(args, root)
  local stdout, code = git.run(args, root)
  return code == 0 and vim.trim(stdout) or ""
end

---@return string?
local function root()
  local r = git.root()
  if not r then
    log.warn "Release: not inside a git repository"
  end
  return r
end

--- The last tag and the commits since it (all of them when there is no tag)
---@param r string
---@return string? tag, ReleaseCommit[]
function M.since(r)
  local tag = out({ "describe", "--tags", "--abbrev=0" }, r)
  tag = tag ~= "" and tag or nil
  local range = tag and (tag .. "..HEAD") or "HEAD"
  local stdout = git.run({ "log", range, "--format=%h%x1f%s%x1f%b%x1e" }, r)
  return tag, changelog.parse(stdout)
end

--- The files a version can be written in
---@param r string
---@return table<string, string>
local function version_files(r)
  local files = {}
  for _, name in ipairs { "VERSION", "package.json", "pubspec.yaml", "Cargo.toml", "pyproject.toml" } do
    files[name] = require("utils.project").read(r .. "/" .. name)
  end
  return files
end

--- The version written in the project, else the last tag's
---@param r string
---@param tag string?
---@return string? version, string? file
local function current(r, tag)
  local v, file = changelog.current(version_files(r))
  if v then
    return v, file
  end
  return tag and tag:gsub("^v", "") or nil, nil
end

--- <leader>GRc: the next version's section at the top of CHANGELOG.md, after a confirmation that shows it
---@param on_done fun()?
function M.changelog(on_done)
  local r = root()
  if not r then
    return
  end
  local tag, commits = M.since(r)
  local version = current(r, tag)
  local next_version, kind = changelog.bump(version, commits)
  if not next_version then
    return log.info(("Release: no commits since %s"):format(tag or "the first commit"))
  end
  local file = cfg().changelog or "CHANGELOG.md"
  local section = changelog.section(next_version, os.date "%Y-%m-%d", commits)
  local modal = require "utils.modal"
  local lines = {
    {
      { ("v%s"):format(next_version), modal.hl.file },
      { ("  %s bump from %s · %d commits"):format(kind, version or "nothing", #commits), modal.hl.muted },
    },
    "",
  }
  for _, l in ipairs(vim.list_slice(vim.split(vim.trim(section), "\n", { plain = true }), 2, 18)) do
    lines[#lines + 1] = { { l, modal.hl.muted } }
  end
  modal.confirm(lines, { title = file, confirm = "Write" }, function()
    local path = r .. "/" .. file
    local new = changelog.insert(require("utils.project").read(path), next_version, section)
    local f, err = io.open(path, "w")
    if not f then
      return log.warn("Release: " .. tostring(err))
    end
    f:write(new)
    f:close()
    vim.cmd.checktime()
    vim.cmd.edit(vim.fn.fnameescape(path))
    log.info(
      ("Release: %s has v%s · then bump the version, commit, `git tag v%s`"):format(file, next_version, next_version)
    )
    if on_done then
      on_done()
    end
  end)
end

--- The branch a PR of this one goes to: origin's HEAD, else main or master
---@param r string
---@return string?
function M.base(r)
  local head = out({ "rev-parse", "--abbrev-ref", "origin/HEAD" }, r)
  if head ~= "" and head ~= "origin/HEAD" then
    return head
  end
  for _, b in ipairs { "origin/main", "origin/master", "main", "master" } do
    if out({ "rev-parse", "--verify", "--quiet", b }, r) ~= "" then
      return b
    end
  end
end

--- The request that writes a PR description (pure)
---@param branch string
---@param base string
---@param subjects string[]
---@param stat string
---@param diff string
---@return table
function M.pr_request(branch, base, subjects, stat, diff)
  return {
    action = "release_pr",
    tier = "light",
    system = [[You write the description of a pull request from its commits and its diff.
Output ONLY the Markdown body, no title line, no ``` fence around it, in English, with exactly these sections:
## Summary
2-4 sentences: what changes for the user or the code, and why.
## Changes
Bullets grouped by area, each a concrete change (name the files, modules or screens).
## How to test
Numbered steps a reviewer follows, with the commands or screens involved.
## Risks
What could break: migrations, configuration, behaviour changes, breaking API changes; "None known" when there are none.
Use only what the commits and the diff show: never invent tickets, numbers or behaviour. Requirement ids (FR-n) the commits name go in Summary.]],
    prompt = ("<branch>%s → %s</branch>\n\n<commits>\n%s\n</commits>\n\n<stat>\n%s\n</stat>\n\n<diff>\n%s\n</diff>\n\nWrite the description."):format(
      branch,
      base,
      table.concat(subjects, "\n"),
      stat,
      diff
    ),
  }
end

--- A scratch Markdown buffer in a split (q closes), reused by name
---@param name string
---@param lines string[]
---@return integer buf
local function show(name, lines)
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].filetype = "markdown"
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if vim.fn.bufwinid(buf) == -1 then
    vim.cmd "botright vsplit"
    vim.api.nvim_win_set_buf(0, buf)
  else
    vim.api.nvim_set_current_win(vim.fn.bufwinid(buf))
  end
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, desc = "Release close" })
  return buf
end

--- <leader>GRp: the description of a PR of this branch (in a buffer and the clipboard; never posted)
function M.pr()
  local r = root()
  if not r then
    return
  end
  local base = M.base(r)
  if not base then
    return log.warn "Release: no base branch found (origin/HEAD, main or master)"
  end
  local branch = out({ "rev-parse", "--abbrev-ref", "HEAD" }, r)
  local subjects = vim.split(out({ "log", base .. "..HEAD", "--format=%s" }, r), "\n", { trimempty = true })
  if #subjects == 0 then
    return log.info(("Release: %s has no commits that %s lacks"):format(branch, base))
  end
  local max = cfg().pr_max_chars or 12000
  local diff = out({ "diff", base .. "...HEAD" }, r)
  if #diff > max then
    diff = diff:sub(1, max) .. "\n… (cut at " .. max .. " characters)"
  end
  local req = M.pr_request(branch, base, subjects, out({ "diff", "--stat", base .. "...HEAD" }, r), diff)
  local sel = require("agent.selection").current { name = req.action, tier = req.tier }
  if not sel then
    return log.warn "Release: no agent backend found (<leader>am)"
  end
  log.info(("Release: describing %d commits with %s…"):format(#subjects, require("agent.selection").label(sel)))
  require("agent").complete(req, function(ok, text)
    if not ok or vim.trim(text or "") == "" then
      return log.warn("Release: no description: " .. tostring(ok and "empty answer" or text))
    end
    local body = require("agent.kit.compose").clean(text)
    vim.fn.setreg("+", body)
    vim.fn.setreg('"', body)
    show("release://pr", vim.split(body, "\n", { plain = true }))
    log.info "Release: PR description copied to the clipboard (paste it in the PR; nothing was posted)"
  end)
end

--- <leader>GRl: the release checklist
function M.checklist()
  local r = root()
  if not r then
    return
  end
  local tag, commits = M.since(r)
  local version, file = current(r, tag)
  local next_version = changelog.bump(version, commits)
  local branch = git.branch(r)
  local log_text = require("utils.project").read(r .. "/" .. (cfg().changelog or "CHANGELOG.md")) or ""
  local ci = {}
  for _, pattern in ipairs {
    ".github/workflows/*.y*ml",
    ".gitlab-ci.yml",
    ".forgejo/workflows/*.y*ml",
    ".gitea/workflows/*.y*ml",
    ".circleci/config.yml",
  } do
    for _, p in ipairs(vim.fn.glob(r .. "/" .. pattern, false, true)) do
      ci[#ci + 1] = p:sub(#r + 2)
    end
  end
  local facts = {
    clean = out({ "status", "--porcelain" }, r) == "",
    branch = branch.name,
    ahead = branch.ahead,
    behind = branch.behind,
    version = version,
    version_file = file,
    next = next_version,
    tag = tag,
    commits = #commits,
    changelog = next_version ~= nil and log_text:find("## [" .. next_version .. "]", 1, true) ~= nil,
    ci = ci,
    stack = require("utils.project").read(r .. "/STACK.md"),
  }
  local lines, actions = require("release.checklist").render(facts)
  local buf = show("release://checklist", lines)
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "<CR>", function()
    local a = actions[vim.api.nvim_win_get_cursor(0)[1]]
    if not a then
      return
    end
    if a.kind == "run" then
      return require("utils.terminal").run(a.cmd, r)
    elseif a.kind == "changelog" then
      return M.changelog(M.checklist)
    elseif a.kind == "open" then
      vim.cmd "wincmd p"
      vim.cmd.edit(vim.fn.fnameescape(r .. "/" .. a.path))
    end
  end, { buffer = buf, nowait = true, desc = "Release act on the line" })
  vim.keymap.set("n", "r", M.checklist, { buffer = buf, nowait = true, desc = "Release read again" })
end

return M
