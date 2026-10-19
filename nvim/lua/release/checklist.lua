-- ── The release checklist, from STACK.md and the repository (pure) ───────────
-- What has to be true before a release, each item checked where it can be (0 tokens): a clean tree, the quality gates
-- STACK.md lists (their commands run in the terminal with ⏎; nothing that pushes, tags, publishes or deploys ever runs
-- from here), the changelog and the version for the next release, CI, and how STACK.md says it ships.
-- Tested in test-release.lua.
local M = {}

-- commands that leave the machine: shown, never run from the checklist
local OUTWARD = { "push", "deploy", "publish", "release", "upload", "tag", "submit", "promote" }

--- Can this command run from the checklist? (local checks only)
---@param cmd string
---@return boolean
function M.runnable(cmd)
  local words = " " .. cmd:lower():gsub("[^%w]", " ") .. " "
  for _, w in ipairs(OUTWARD) do
    if words:find(" " .. w .. " ", 1, true) then
      return false
    end
  end
  return true
end

--- The commands of STACK.md's "Quality gates" (backticked, in its bullets or rows); "Commands" rows about tests, lint,
--- format, types or build when it has none
---@param stack string
---@return string[]
function M.gates(stack)
  local function cmds(body, filter)
    local out, seen = {}, {}
    for line in (body or ""):gmatch "[^\n]+" do
      if not filter or filter(line:lower()) then
        for cmd in line:gmatch "`([^`]+)`" do
          if cmd:find " " and not seen[cmd] then -- a command has words; a lone `name` is a tool, not a command
            seen[cmd] = true
            out[#out + 1] = cmd
          end
        end
      end
    end
    return out
  end
  local text = (stack or "") .. "\n## "
  local gates = cmds(text:match "\n## Quality gates%s*\n(.-)\n## ")
  if #gates > 0 then
    return gates
  end
  return cmds(text:match "\n## Commands%s*\n(.-)\n## ", function(l)
    return l:find "test" or l:find "lint" or l:find "format" or l:find "type" or l:find "build" or l:find "check"
  end)
end

--- How STACK.md says the project ships: its Stack rows about deploy, release, hosting, distribution, CI
---@param stack string
---@return string[]
function M.shipping(stack)
  local out = {}
  local table_text = ((stack or "") .. "\n## "):match "\n## Stack%s*\n(.-)\n## " or ""
  for row in table_text:gmatch "[^\n]+" do
    local key, value = row:match "^|%s*([^|]-)%s*|%s*([^|]-)%s*|"
    if key and not row:match "^|%s*%-" then
      local k = key:lower()
      if
        k:find "deploy"
        or k:find "release"
        or k:find "host"
        or k:find "distribut"
        or k:find "store"
        or k:find "^ci"
      then
        out[#out + 1] = ("%s: %s"):format(key:gsub("%*", ""), value:gsub("%*", ""))
      end
    end
  end
  return out
end

---@class ReleaseFacts
---@field clean boolean          no uncommitted changes
---@field branch string
---@field ahead integer
---@field behind integer
---@field version string?        the version written in the project
---@field version_file string?
---@field next string?           the version the commits since the last tag call for
---@field tag string?            the last tag
---@field commits integer        commits since it
---@field changelog boolean      CHANGELOG.md has a section for `next`
---@field ci string[]            CI files there are
---@field stack string?

--- The checklist as Markdown, and what ⏎ does on each line (pure)
---@param facts ReleaseFacts
---@return string[] lines, table<integer, table> actions
function M.render(facts)
  local lines, actions = {}, {}
  local function add(text, action)
    lines[#lines + 1] = text
    actions[#lines] = action
  end
  local function item(done, text, action)
    add(("- [%s] %s"):format(done and "x" or " ", text), action)
  end
  add("# Release · " .. (facts.next and ("v" .. facts.next) or "nothing new"))
  add ""
  add(
    ("%d commit%s since %s · ⏎ runs a check or fixes an item · r reads again · q closes"):format(
      facts.commits,
      facts.commits == 1 and "" or "s",
      facts.tag or "the first commit"
    )
  )
  add ""
  add "## Repository"
  add ""
  item(facts.clean, facts.clean and "working tree clean" or "uncommitted changes: commit or stash them (<leader>Gc)")
  item(
    facts.behind == 0,
    ("on `%s` · %d ahead, %d behind its upstream"):format(facts.branch, facts.ahead, facts.behind)
  )
  add ""
  add "## Quality gates (STACK.md)"
  add ""
  local gates = facts.stack and M.gates(facts.stack) or {}
  if #gates == 0 then
    add "No commands in STACK.md's Quality gates (or Commands): add them there."
  end
  for _, cmd in ipairs(gates) do
    if M.runnable(cmd) then
      item(false, ("`%s` · ⏎ runs it"):format(cmd), { kind = "run", cmd = cmd })
    else
      item(false, ("`%s` (by hand: it leaves the machine)"):format(cmd))
    end
  end
  add ""
  add "## Version and changelog"
  add ""
  if facts.next then
    item(facts.changelog, ("CHANGELOG.md has v%s · ⏎ writes it"):format(facts.next), { kind = "changelog" })
    local bumped = facts.version == facts.next
    item(
      bumped,
      facts.version_file and ("%s says %s (next: %s)"):format(facts.version_file, facts.version or "?", facts.next)
        or ("no version file: the tag v%s is the version"):format(facts.next),
      facts.version_file and { kind = "open", path = facts.version_file } or nil
    )
    item(false, ("tag it: `git tag v%s` then `git push --tags` (by hand)"):format(facts.next))
  else
    add "Nothing to release: no commits since the last tag."
  end
  add ""
  add "## Shipping"
  add ""
  item(#facts.ci > 0, #facts.ci > 0 and ("CI: " .. table.concat(facts.ci, ", ")) or "no CI configuration found")
  for _, s in ipairs(facts.stack and M.shipping(facts.stack) or {}) do
    add("- " .. s)
  end
  return lines, actions
end

return M
