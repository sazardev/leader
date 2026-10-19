-- ── Project kit: what the model is asked ─────────────────────────────────────
-- One request per document. Each one names the sections it must have (compose.DOCS, the same list the presets are checked
-- against), so a preset and a written document read the same way. Pure: returns { action, system, prompt, tier }.
local compose = require "agent.kit.compose"

local M = {}

local SYSTEM =
  [[You write the project documents that coding agents (Claude Code, Codex, Cursor, opencode…) read before they change code.
Output ONLY the Markdown file: it starts with the `# ` title line, nothing before or after it, no ``` fence around it.
Be dense and concrete: imperative rules an agent can follow and a reviewer can check, real names, real commands, real numbers. No filler, no marketing, no emojis.]]

--- One section of a document (the rest stays as the user has it)
local SECTION_SYSTEM = SYSTEM:gsub(
  "Output ONLY the Markdown file: it starts with the `# ` title line",
  "Output ONLY the Markdown section asked for: it starts with its `## ` heading"
)

--- About the project: what is not in the input is not made up
local FACTS = "Never invent facts: what the input does not say and you cannot infer goes to a `TODO:` line."
--- A stack or a design is a set of choices: making them is the job
local DECIDE = "Decide: where the description leaves a choice open, pick the mature, widely used option, state it as THE choice "
  .. "and mark it `(proposed)` (say why in one line). `TODO:` is only for facts only the user knows (accounts, providers "
  .. "under contract, brand names), never for a technical choice you can make."

--- The last lines of every request (the model weighs the end most): the title, the stance, the language
---@param file string
---@param name string what goes after the file name in the title
---@param stance string
---@return string
local function closing(file, name, stance)
  local lang = (require("core.settings").agent.kit or {}).language or "English"
  return (
    "\n\nThe first line is exactly: `# %s: %s`.\n%s\nLanguage: write EVERY line in %s, including what comes from the "
    .. "input in another language (translate it; keep proper names, code and domain terms with no good translation as they "
    .. "are). Never mix languages."
  ):format(file, name, stance, lang)
end

---@param id string
---@return string
local function sections(id)
  return table.concat(
    vim.tbl_map(function(s)
      return "## " .. s
    end, compose.doc(id).sections),
    "\n"
  )
end

---@param tag string
---@param text string?
---@return string
local function block(tag, text)
  if not text or vim.trim(text) == "" then
    return ""
  end
  return ("<%s>\n%s\n</%s>\n\n"):format(tag, vim.trim(text), tag:match "^%S+")
end

---@param facts KitFacts
---@return string
local function project(facts)
  local parts = {}
  parts[#parts + 1] = ("name: %s"):format(facts.name)
  if #facts.languages > 0 then
    parts[#parts + 1] = "languages (files): "
      .. table.concat(
        vim.tbl_map(function(l)
          return ("%s %d"):format(l.name, l.files)
        end, vim.list_slice(facts.languages, 1, 8)),
        ", "
      )
  end
  if #facts.commands > 0 then
    parts[#parts + 1] = "commands found: "
      .. table.concat(
        vim.tbl_map(function(c)
          return c.label .. " = `" .. c.cmd .. "`"
        end, facts.commands),
        "; "
      )
  end
  if #facts.targets > 0 then
    parts[#parts + 1] = "Makefile targets: " .. table.concat(vim.list_slice(facts.targets, 1, 40), ", ")
  end
  local out = block("project", table.concat(parts, "\n"))
  out = out .. block("tree", table.concat(require("agent.kit.snapshot").tree(facts.files), "\n"))
  local names = vim.tbl_keys(facts.manifests)
  table.sort(names)
  for _, name in ipairs(names) do
    out = out .. block('file path="' .. name .. '"', facts.manifests[name])
  end
  out = out .. block("readme", facts.readme)
  return out
end

--- The other kit documents' text (STACK.md, SPEC.md, DESIGN.md), each clipped: in a project with no code yet they ARE the
--- facts AGENTS.md is written from
---@param facts KitFacts
---@return string
local function documents(facts)
  local out = ""
  for _, d in ipairs(compose.DOCS) do
    local text = d.id ~= "agents" and facts.docs[d.file]
    if text then
      if #text > 6000 then
        text = text:sub(1, 6000) .. "\n…"
      end
      out = out .. block('document path="' .. d.file .. '"', text)
    end
  end
  return out
end

--- AGENTS.md from the project (and the one already there, when it is an update)
---@param facts KitFacts
---@return table
function M.agents(facts)
  local others = {}
  for _, d in ipairs(compose.DOCS) do
    if d.id ~= "agents" and facts.docs[d.file] then
      others[#others + 1] = ("- [%s](%s): %s."):format(d.file, d.file, d.about)
    end
  end
  local current = facts.docs["AGENTS.md"]
  local task = ([[Write AGENTS.md for this repository: the file every coding agent reads first.
It has exactly these sections, in this order:
%s

- Project: what it is and for whom, in 2-4 sentences, from the README and the code; the main languages and frameworks.
- Read first: one line per document below (link + why), then "read the code around a change before writing".
%s
- Commands: a table Task | Command with the REAL commands (install, build, test, a single test, lint, format, run, generate…) from the Makefile, scripts and manifests. Never guess a command that is not backed by the input.
- Layout: the top folders and what lives in each, from the tree; the dependency direction between layers if the tree shows one.
- Conventions: naming, file organisation (one file = one responsibility), error handling, logging, tests next to code or not… as the code shows them.
- Workflow: numbered steps from understanding the task to the commit (Conventional Commits).
- Boundaries: what an agent must never do here (secrets, generated files, lockfiles, unrelated rewrites, new dependencies without asking…) and what needs asking first.
- Definition of done: checkable items (builds, lint clean, tests pass, docs still true, minimal diff).
Keep it under ~120 lines: an agent reads it on every task.
%s]]):format(
    sections "agents",
    #others > 0 and ("Documents to link:\n" .. table.concat(others, "\n"))
      or "No other documents yet: say so in one TODO line.",
    current
        and "An AGENTS.md exists (in <current>): keep everything in it that is still true and specific, fix what the project contradicts, fill the missing sections."
      or ""
  )
  return {
    action = "kit_agents",
    tier = "main",
    system = SYSTEM,
    prompt = project(facts)
      .. documents(facts)
      .. block("current", current)
      .. task
      .. closing(
        "AGENTS.md",
        facts.name,
        FACTS
          .. " The other documents count as input: with little or no code yet, take the purpose from SPEC.md and the commands, layout and conventions from STACK.md."
      ),
  }
end

--- SPEC.md from what the user wrote (or rewrote) in the draft
---@param draft string
---@param facts KitFacts?
---@return table
function M.spec(draft, facts)
  local task = ([[Turn what the user wrote in <draft> into SPEC.md: the specification coding agents implement from.
It has exactly these sections, in this order:
%s

- Keep the user's intent, words and decisions; reorganise, deduplicate and make it precise. Do not add features they did not ask for.
- Summary: 2-3 sentences. Problem: who hurts and why now.
- Goals: measurable outcomes. Non-goals: what is explicitly out (infer only the obvious ones the draft implies).
- Users and scenarios: personas and the main flows as short numbered steps.
- Requirements: numbered `FR-1`, `FR-2`… each with a one-line statement in "The system must…" form and acceptance criteria as Given/When/Then bullets. Keep existing ids when the draft already has them.
- Non-functional requirements: `NFR-1`… (performance with numbers, security, privacy, availability, accessibility, i18n) only those the draft states or clearly needs.
- Data: entities, their fields and relations as a table or list. Interfaces: screens, endpoints, commands or events with their inputs and outputs.
- Edge cases: what can go wrong and what must happen.
- Open questions: every gap, ambiguity or contradiction you found, as a question to the user. Never fill a gap with an invention: elsewhere, point to the question (`see Q3`) instead of a TODO.
- Milestones: thin vertical slices in delivery order, each one shippable.]]):format(sections "spec")
  return {
    action = "kit_spec",
    tier = "main",
    system = SYSTEM,
    prompt = (facts and block("project", facts.name .. (facts.readme and ("\n" .. facts.readme) or "")) or "")
      .. block("draft", draft)
      .. task
      .. closing("SPEC.md", "<what is being built, in 2-5 words>", (FACTS:gsub("a `TODO:` line", "Open questions"))),
  }
end

--- DESIGN.md from a description (and the preset it names, as the base)
---@param description string
---@param base KitPreset?
---@param names string[] the design presets there are (the model may be asked "like X")
---@param addons string[]? the design add-ons merged afterwards (platforms, theme, palette, motion…)
---@return table
function M.design(description, base, names, addons)
  local task = ([[Write DESIGN.md: the design system coding agents follow when they build UI, from the user's description in <description>.
It has exactly these sections, in this order:
%s

- Principles: 4-6 principles that decide trade-offs, each one sentence.
- Color: semantic tokens (background, surface, surface-raised, text, text-muted, border, primary, on-primary, accent, success, warning, danger, info, focus) as a table Token | Light | Dark | Use, with hex values; contrast of text pairs at least 4.5:1.
- Typography: font families with fallbacks, a type scale table Role | Size/line height | Weight | Use, numeric figures rule.
- Spacing and layout: the base unit and scale, grid/breakpoints, max content width, density.
- Shape and elevation: radius scale, borders, shadows/elevation levels (or why there are none).
- Motion: durations and easing curves as tokens, what animates and what never does, reduced-motion rule.
- Components: rules for buttons, inputs, forms, lists/tables, navigation, dialogs, toasts, empty/loading/error states.
- Accessibility: WCAG 2.2 AA rules that apply: contrast, focus visible, target sizes, keyboard, screen readers.
- Rules for agents: how to implement it: tokens as CSS variables / theme objects, never hardcode a value that has a token, which component library maps to it, what to do when a token is missing.
Known designs the user may name: %s.
For a terminal UI (TUI, CLI) translate every section to the terminal: colors as ANSI 16 / 256 / truecolor with fallbacks, typography as monospace cells and glyph sets, spacing in cells, shape as box-drawing borders, motion as frame-based animation, accessibility as NO_COLOR, contrast, screen readers and keyboard-only.
%s%s]]):format(
    sections "design",
    table.concat(names, ", "),
    (addons and #addons > 0)
        and ("These add-ons are merged afterwards (rows with the same first word replace yours): " .. table.concat(
          addons,
          ", "
        ) .. ". Stay consistent with them and do not describe them yourself.\n")
      or "",
    base
        and "The description builds on the system in <base>: keep its structure and values, change only what the description asks."
      or ""
  )
  return {
    action = "kit_design",
    tier = "main",
    system = SYSTEM,
    prompt = block("base", base and base.body)
      .. block("description", description)
      .. task
      .. closing("DESIGN.md", "<product or style, in 2-5 words>", DECIDE),
  }
end

--- DESIGN.md's `## Screens` section: a wireframe of every main screen SPEC.md names, drawn in DESIGN.md's own style. Models
--- copy a picture far more faithfully than prose, so the build lays screens out as drawn.
---@param spec string
---@param design string
---@param stack string?
---@return table
function M.screens(spec, design, stack)
  local summary = stack and (stack:match "## Summary%s*\n(.-)\n## " or ""):sub(1, 1500) or ""
  local task =
    [[Write the `## Screens` section of DESIGN.md (in <design>) for the product in <spec>: one wireframe per main screen and per state that changes the layout (empty, error, too small), in the style DESIGN.md defines.
Output ONLY the section: it starts with `## Screens`, no other `## ` heading, no fence around the whole answer.
For each screen:
- `### <Screen name>` and one line: what it is for and which SPEC requirements (FR-n) it serves.
- A ``` fenced wireframe drawn character by character as it renders: the real borders, glyphs and labels from DESIGN.md, real sample content (not "Lorem"), aligned exactly. Terminal UI: at the minimum size the documents name (else 80x24), every line exactly that wide (pad with spaces), the composition centered when DESIGN.md says so. GUI: about 100 columns for the widest layout, plus a narrow (mobile) variant when the product has one.
- Under it, a short list: each region with its tokens (color, type, spacing), alignment, fixed vs flexible sizes, focus/selection, and how it adapts when the window is bigger or smaller.
Keep it consistent with DESIGN.md's components and rules; where SPEC leaves a layout choice open, decide and mark it `(proposed)`.]]
  return {
    action = "kit_screens",
    tier = "main",
    timeout_ms = 300000, -- several screens drawn cell by cell, after a long think
    system = SECTION_SYSTEM,
    prompt = block("spec", spec)
      .. block("design", design)
      .. block("stack-summary", summary)
      .. task
      .. ("\n\nThe first line is exactly: `## Screens`.\nLanguage: write every line in %s; the labels on screen as SPEC.md writes them."):format(
        (require("core.settings").agent.kit or {}).language or "English"
      ),
  }
end

--- STACK.md from a description; the principles are added afterwards from presets (only their names go to the model)
---@param description string
---@param principles string[] names of the principles that will be added
---@param facts KitFacts?
---@param addons string[]? names of the add-ons merged afterwards (deploy, CI…)
---@return table
function M.stack(description, principles, facts, addons)
  local task = ([[Write STACK.md: the technical stack and the project layout coding agents follow, from the user's description in <description>.
It has exactly these sections, in this order:
%s

- Summary: what kind of project, the architecture style in one paragraph.
- Stack: a table Layer | Choice | Why (language and version, framework, data, auth, UI, testing, tooling, deploy). Prefer mature, boring, well-maintained choices; name versions when they matter.
- Project layout: a tree of folders and representative files, organised by feature/module, with one responsibility per file, and the allowed dependency direction between layers.
- Conventions: naming, file size limits, error handling, configuration, logging, how a new feature is added (which files, in which folders).
- Commands: the real commands to install, run, test, lint, format, generate, migrate.
- Testing: what is tested how (unit, integration, end-to-end), where tests live, test data, coverage expectations.
- Quality gates: formatter, linter with its strictness, type checking, CI checks a change must pass.
- Dependencies: the policy (when a library is allowed), and what NOT to use and why.
- Rules for agents: 8-15 imperative rules specific to this stack.
Do NOT write an "Engineering principles" section: it is appended afterwards with: %s. Make the layout and rules consistent with them.%s]]):format(
    sections "stack",
    #principles > 0 and table.concat(principles, ", ") or "none",
    (addons and #addons > 0)
        and ("\nThese add-ons are merged afterwards (their rows replace yours with the same first word): " .. table.concat(
          addons,
          ", "
        ) .. ". Choose consistently with them and do not describe them yourself.")
      or ""
  )
  return {
    action = "kit_stack",
    tier = "main",
    system = SYSTEM,
    prompt = (facts and project(facts) or "")
      .. block("description", description)
      .. task
      .. closing("STACK.md", "<the stack, e.g. Python + FastAPI + Postgres>", DECIDE),
  }
end

--- One new requirement for SPEC.md from what the user wrote: JSON the kit renders in SPEC.md's own style (feature.lua)
---@param draft string
---@param spec string the current SPEC.md (its terms, entities and ids)
---@param next_id string "FR-8"
---@return table
function M.feature(draft, spec, next_id)
  local lang = (require("core.settings").agent.kit or {}).language or "English"
  return {
    action = "kit_feature",
    tier = "main",
    system = [[You add ONE requirement to a project's SPEC.md, the specification coding agents implement from.
Output ONLY one JSON object, no prose, no ``` fence:
{"title": "<2-5 words>",
 "statement": "<one sentence: The system must…>",
 "criteria": ["Given <state>, when <action>, then <exactly what the user sees or gets>"],
 "edge_cases": ["<what can go wrong>: <what must happen>"],
 "questions": ["<a gap only the user can answer, as a question>"],
 "builds_on": ["<FR-n of SPEC.md this one relies on>"]}
Rules:
- Keep the user's intent and words; use the terms, entities and screens SPEC.md already names. Do not add features they did not ask for.
- 2-6 acceptance criteria, each one testable as written: concrete values, what is shown, errors with their text.
- Never fill a gap with an invention: it goes to `questions` (an empty list when there is none).]]
      .. ("\nWrite every string in %s, including what the user wrote in another language."):format(lang),
    prompt = block("spec", spec)
      .. block("draft", draft)
      .. ("This requirement will be %s. Answer the JSON object."):format(next_id),
  }
end

return M
