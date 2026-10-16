-- ── Project kit: AGENTS.md without a model (pure) ────────────────────────────
-- The same sections the agent writes, filled from the snapshot's facts (commands, languages, folders, the kit documents that
-- are there) and the rules that hold for any project. What only a person knows is left as a `TODO:` line to fill in.
local compose = require "agent.kit.compose"

local M = {}

---@param facts KitFacts
---@return string
function M.agents(facts)
  local out = {}
  local function add(...)
    for _, line in ipairs { ... } do
      out[#out + 1] = line
    end
  end

  local langs = vim.tbl_map(function(l)
    return l.name
  end, vim.list_slice(facts.languages, 1, 4))
  add(
    "# AGENTS.md: " .. facts.name,
    "",
    "Instructions for coding agents (and people) working in this repository. Keep it short and true.",
    ""
  )

  add("## Project", "")
  add(("**%s**: TODO: one sentence on what it is and who uses it."):format(facts.name))
  if #langs > 0 then
    add("", "Written in " .. table.concat(langs, ", ") .. ".")
  end
  add ""

  add("## " .. compose.LINKS, "")
  local any = false
  for _, d in ipairs(compose.DOCS) do
    if d.id ~= "agents" and facts.docs[d.file] then
      any = true
      add(("- [%s](%s): %s."):format(d.file, d.file, d.about))
    end
  end
  if not any then
    add "- TODO: the documents an agent must read before changing code (STACK.md, DESIGN.md, SPEC.md: `<leader>aS`)."
  end
  add("- Read the code around a change before writing: follow what is there, not what is usual elsewhere.", "")

  add("## Commands", "")
  if #facts.commands == 0 then
    add "- TODO: how to build, test, lint and run it."
  else
    add("| Task | Command |", "| --- | --- |")
    for _, c in ipairs(facts.commands) do
      add(("| %s | `%s` |"):format(c.label, c.cmd))
    end
  end
  add ""

  add("## Layout", "", "```")
  local rows = require("agent.kit.snapshot").tree(facts.files, 40, 1)
  for _, row in ipairs(rows) do
    if not row:match "^%s" then -- first level only: the rest changes too often to keep here
      add(row)
    end
  end
  add("```", "", "TODO: one line per top folder saying what lives there.", "")

  add(
    "## Conventions",
    "",
    "- One file, one responsibility. A file that does two things is two files.",
    "- Names say what a thing is or does; no abbreviations that are not already in the code.",
    "- Small functions with one level of abstraction; return early instead of nesting.",
    "- Errors are handled or returned with context, never swallowed.",
    "- No dead code, no commented-out code, no TODO without an owner or an issue.",
    "- Match the formatter and linter in Commands; a change that adds warnings is not done.",
    ""
  )

  add(
    "## Workflow",
    "",
    "1. Understand the task and find the code it touches; ask when the requirement is ambiguous.",
    "2. Plan the smallest change that solves it; say which files change and why.",
    "3. Write the test first when the behaviour is new or a bug is being fixed.",
    "4. Make the change, then run format, lint and the tests from Commands.",
    "5. Commit with Conventional Commits (`feat(scope): …`, `fix(scope): …`), one logical change per commit.",
    ""
  )

  add(
    "## Boundaries",
    "",
    "- Never commit secrets, tokens or `.env` files; never print them in logs.",
    "- Never add a dependency without saying why the standard library or an existing one is not enough.",
    "- Never edit generated files, lockfiles by hand, or vendored code.",
    "- Never rewrite unrelated code in the same change; never disable a test or a lint rule to make a change pass.",
    "- Ask before deleting files, changing public APIs, database schemas or CI.",
    ""
  )

  add(
    "## Definition of done",
    "",
    "- It builds, the linter is clean and every test passes.",
    "- New behaviour has tests; a fixed bug has a test that failed before the fix.",
    "- The documents in Read first still say the truth (update them in the same change).",
    "- The diff contains only what the task needs."
  )
  return table.concat(out, "\n") .. "\n"
end

return M
