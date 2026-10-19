-- ── Project kit: the documents' text (pure) ──────────────────────────────────
-- What the four documents are, the sections each must have, and the text work around them: cleaning a model's answer,
-- the STACK.md's "Engineering principles" section (made of principle presets), the links AGENTS.md keeps to the others,
-- and which design preset a free description names. No IO: tested in scripts/test-kit.lua.
local M = {}

---@class KitDoc
---@field id string
---@field file string
---@field about string   one line: why an agent should read it (the link in AGENTS.md)
---@field sections string[]  the `## ` headings it must have (presets are checked against them, the model is asked for them)

---@type KitDoc[]
M.DOCS = {
  {
    id = "agents",
    file = "AGENTS.md",
    about = "how to work in this repository",
    sections = {
      "Project",
      "Read first",
      "Commands",
      "Layout",
      "Conventions",
      "Workflow",
      "Boundaries",
      "Definition of done",
    },
  },
  {
    id = "stack",
    file = "STACK.md",
    about = "the stack, the project layout and the engineering rules every change follows",
    sections = {
      "Summary",
      "Stack",
      "Project layout",
      "Conventions",
      "Commands",
      "Testing",
      "Quality gates",
      "Dependencies",
      "Rules for agents",
    },
  },
  {
    id = "design",
    file = "DESIGN.md",
    about = "the design system: tokens, components and UI rules",
    sections = {
      "Principles",
      "Color",
      "Typography",
      "Spacing and layout",
      "Shape and elevation",
      "Motion",
      "Components",
      "Accessibility",
      "Rules for agents",
    },
    -- sections a DESIGN.md may add: the toolkit add-ons' mapping, the screens drawn by <leader>aSw
    optional = { "Toolkit", "Screens" },
  },
  {
    id = "spec",
    file = "SPEC.md",
    about = "what is being built: requirements, acceptance criteria and open questions",
    sections = {
      "Summary",
      "Problem",
      "Goals",
      "Non-goals",
      "Users and scenarios",
      "Requirements",
      "Non-functional requirements",
      "Data",
      "Interfaces",
      "Edge cases",
      "Open questions",
      "Milestones",
    },
  },
}

---@param id string
---@return KitDoc
function M.doc(id)
  for _, d in ipairs(M.DOCS) do
    if d.id == id then
      return d
    end
  end
  error("kit: unknown document " .. tostring(id))
end

M.PRINCIPLES = "Engineering principles"
local PRINCIPLES_INTRO = "Rules, not suggestions: every change follows them, and a review checks them. "
  .. "When one has to be broken, say so in the change and why."

---@param text string
---@return string[]
local function lines_of(text)
  return vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
end

---@param lines string[]
---@return string
local function join(lines)
  return (table.concat(lines, "\n"):gsub("%s+$", "")) .. "\n"
end

--- A model's answer as a file: no chatter before the first heading, no ```markdown fence around it
---@param text string
---@return string
function M.clean(text)
  local lines = lines_of(vim.trim(text or ""))
  local fenced = false
  for i, line in ipairs(lines) do
    if line:match "^```" then
      fenced = true
    elseif line:match "^#%s" then
      lines = vim.list_slice(lines, i)
      break
    end
  end
  if fenced and lines[#lines] and lines[#lines]:match "^```%s*$" then -- the fence that wrapped the whole answer
    lines[#lines] = nil
  end
  if lines[1] and lines[1]:match "^```" then -- a fence with no heading inside
    table.remove(lines, 1)
  end
  return join(lines)
end

--- The `## ` headings of a Markdown text (outside code fences)
---@param text string
---@return string[]
function M.headings(text)
  local out, fenced = {}, false
  for _, line in ipairs(lines_of(text)) do
    if line:match "^```" then
      fenced = not fenced
    elseif not fenced then
      local h = line:match "^##%s+(.-)%s*$"
      if h then
        out[#out + 1] = h
      end
    end
  end
  return out
end

--- The sections the document should have and the text lacks
---@param text string
---@param id string
---@return string[]
function M.missing(text, id)
  local have = {}
  for _, h in ipairs(M.headings(text)) do
    have[h:lower()] = true
  end
  return vim.tbl_filter(function(s)
    return not have[s:lower()]
  end, M.doc(id).sections)
end

--- Where a `## Title` section starts and ends (1-based, inclusive), or nil
---@param lines string[]
---@param title string
---@return integer?, integer?
local function section(lines, title)
  local first
  for i, line in ipairs(lines) do
    local h = line:match "^##%s+(.-)%s*$"
    if first and line:match "^#?#%s" then
      return first, i - 1
    end
    if h and h:lower() == title:lower() then
      first = i
    end
  end
  if first then
    return first, #lines
  end
end

--- The principles a STACK.md already carries (their `### ` titles inside the section)
---@param text string
---@return string[]
function M.principles_in(text)
  local lines = lines_of(text)
  local first, last = section(lines, M.PRINCIPLES)
  local out = {}
  for i = first or 1, first and last or 0 do
    local h = lines[i]:match "^###%s+(.-)%s*$"
    if h then
      out[#out + 1] = h
    end
  end
  return out
end

--- The "Engineering principles" section made of the chosen presets (each body starts with its `### ` title)
---@param chosen KitPreset[]
---@return string
function M.principles_section(chosen)
  local out = { "## " .. M.PRINCIPLES, "", PRINCIPLES_INTRO }
  for _, p in ipairs(chosen) do
    out[#out + 1] = ""
    out[#out + 1] = vim.trim(p.body)
  end
  return join(out)
end

--- The STACK.md with its principles section replaced (or added at the end); none chosen removes it
---@param text string
---@param chosen KitPreset[]
---@return string
function M.set_principles(text, chosen)
  local lines = lines_of(text)
  local first, last = section(lines, M.PRINCIPLES)
  if first then
    for _ = first, last do
      table.remove(lines, first)
    end
    while lines[first - 1] == "" do
      table.remove(lines, first - 1)
      first = first - 1
    end
  end
  local body = join(lines)
  if #chosen == 0 then
    return body
  end
  local block = M.principles_section(chosen)
  if first and first <= #lines then -- it was in the middle: put it back where it was
    local before = vim.list_slice(lines, 1, first - 1)
    local after = vim.list_slice(lines, first)
    return join(vim.list_extend(vim.list_extend(before, { "", vim.trim(block), "" }), after))
  end
  return body .. "\n" .. block
end

M.SCREENS = "Screens"

--- The DESIGN.md with its `## Screens` section (wireframes) replaced, or added before "Rules for agents" (else at the end)
---@param text string
---@param screens string the section, with or without its `## Screens` heading
---@return string
function M.set_screens(text, screens)
  local body = vim.trim(screens):gsub("^##%s+[Ss]creens%s*\n", "")
  local block = { "## " .. M.SCREENS, "" }
  vim.list_extend(block, lines_of(vim.trim(body)))
  local lines = lines_of(text)
  local first, last = section(lines, M.SCREENS)
  if first then
    local out = vim.list_slice(lines, 1, first - 1)
    vim.list_extend(out, block)
    if last < #lines then -- the next section, one blank line after the wireframes
      out[#out + 1] = ""
    end
    return join(vim.list_extend(out, vim.list_slice(lines, last + 1)))
  end
  local at = section(lines, "Rules for agents")
  if not at then
    return join(lines):gsub("\n*$", "") .. "\n\n" .. join(block)
  end
  local out = vim.list_slice(lines, 1, at - 1)
  vim.list_extend(out, block)
  out[#out + 1] = ""
  return join(vim.list_extend(out, vim.list_slice(lines, at)))
end

-- ── Add-ons: a preset's sections merged into a STACK.md ─────────────────────
-- An add-on is a small Markdown file with some of the STACK.md's `## ` sections. Its table rows (`| Deploy | … |`) replace the
-- row whose first cell starts with the same word in that section's table (or are added at its end); every other line is added
-- at the end of the section unless it is already there. Applying an add-on twice changes nothing.

---@param row string
---@return string? the first word of the first cell, lowercased ("lint" for `| Lint/format | … |`)
local function row_key(row)
  local cell = row:match "^|%s*([^|]-)%s*|"
  if not cell or cell:match "^%-+$" or cell:match "^:?%-+:?$" then
    return nil
  end
  return (cell:gsub("[`*]", ""):match "^[%w]+" or ""):lower()
end

---@param lines string[]
---@return table<string, { first: integer, last: integer }> each `## ` section by lowercased title: its heading row and last row
local function sections_of(lines)
  local starts = {}
  for i, line in ipairs(lines) do
    if line:match "^##%s" then
      starts[#starts + 1] = i
    end
  end
  local out = {}
  for k, i in ipairs(starts) do
    local name = lines[i]:match("^##%s+(.-)%s*$"):lower()
    out[name] = out[name] or { first = i, last = (starts[k + 1] or #lines + 1) - 1 }
  end
  return out
end

---@param text string addon body
---@return { title: string, rows: string[], lines: string[] }[]
local function addon_sections(text)
  local out, cur = {}, nil
  for _, line in ipairs(lines_of(text)) do
    local h = line:match "^##%s+(.-)%s*$"
    if h and not line:match "^###" then
      cur = { title = h, rows = {}, lines = {} }
      out[#out + 1] = cur
    elseif cur then
      if line:match "^|" then
        if row_key(line) then
          cur.rows[#cur.rows + 1] = line
        end
      elseif line ~= "" or #cur.lines > 0 then
        cur.lines[#cur.lines + 1] = line
      end
    end
  end
  for _, sec in ipairs(out) do
    while sec.lines[#sec.lines] == "" do
      sec.lines[#sec.lines] = nil
    end
  end
  return out
end

--- The STACK.md with the add-on merged in
---@param text string
---@param addon string the add-on's body
---@return string
function M.merge(text, addon)
  local lines = lines_of(text)
  for _, add in ipairs(addon_sections(addon)) do
    local sec = sections_of(lines)[add.title:lower()]
    if not sec then -- a section the STACK.md lacks: added before the principles (or at the end)
      local at = #lines + 1
      local p = sections_of(lines)[M.PRINCIPLES:lower()]
      if p then
        at = p.first
      end
      local block = { "## " .. add.title, "" }
      vim.list_extend(block, add.rows)
      if #add.rows > 0 and #add.lines > 0 then
        block[#block + 1] = ""
      end
      vim.list_extend(block, add.lines)
      block[#block + 1] = ""
      if lines[at - 1] and lines[at - 1] ~= "" then
        table.insert(block, 1, "")
      end
      for k = #block, 1, -1 do
        table.insert(lines, at, block[k])
      end
    else
      -- rows: replace by key inside the section's first table, else after its last row
      for _, row in ipairs(add.rows) do
        sec = sections_of(lines)[add.title:lower()]
        local key, replaced, last_row = row_key(row), false, nil
        for i = sec.first + 1, sec.last do
          if lines[i]:match "^|" then
            last_row = i
            if row_key(lines[i]) == key then
              lines[i] = row
              replaced = true
              break
            end
          elseif last_row then
            break -- only the first table
          end
        end
        if not replaced then
          if last_row then
            table.insert(lines, last_row + 1, row)
          else
            local at = sec.last + 1
            while at - 1 > sec.first and lines[at - 1] == "" do
              at = at - 1
            end
            table.insert(lines, at, "")
            table.insert(lines, at + 1, row)
          end
        end
      end
      -- other lines: at the end of the section, those not there yet; a ``` block is one piece (added whole, or not at all)
      sec = sections_of(lines)[add.title:lower()]
      local body = table.concat(vim.list_slice(lines, sec.first, sec.last), "\n")
      local have = {}
      for i = sec.first, sec.last do
        have[lines[i]] = true
      end
      local new, block = {}, nil
      for _, line in ipairs(add.lines) do
        if block then
          block[#block + 1] = line
          if line:match "^```%s*$" then
            local text = table.concat(block, "\n")
            if not body:find(text, 1, true) then
              vim.list_extend(new, block)
            end
            block = nil
          end
        elseif line:match "^```" then
          block = { line }
        elseif line == "" then
          if #new > 0 and new[#new] ~= "" then
            new[#new + 1] = line
          end
        elseif not have[line] then
          new[#new + 1] = line
        end
      end
      while new[#new] == "" do
        new[#new] = nil
      end
      local meaningful = #new > 0
      if meaningful then
        local at = sec.last + 1
        while at - 1 > sec.first and lines[at - 1] == "" do
          at = at - 1
        end
        local list = "^%s*[-*] "
        if not (lines[at - 1] and lines[at - 1]:match(list) and new[1]:match(list)) then -- bullets continue the list
          table.insert(new, 1, "")
        end
        for k = #new, 1, -1 do
          table.insert(lines, at, new[k])
        end
      end
    end
  end
  return join(lines)
end

--- Is every row and line of the add-on already in the STACK.md? (the customize list checks it)
---@param text string
---@param addon string
---@return boolean
function M.applied(text, addon)
  return M.merge(text, addon) == join(lines_of(text))
end

-- ── Package manager: a pnpm preset written for bun or npm ────────────────────

M.PACKAGE_MANAGERS = {
  pnpm = "| Package manager | pnpm | Fast, strict `node_modules`, workspaces |",
  bun = "| Package manager | Bun (`bun install`, `bun.lock`; Node stays the runtime) | Fastest installs; also runs scripts (`bun run`) |",
  npm = "| Package manager | npm (`package-lock.json`, `npm ci` in CI) | Ships with Node: nothing to install |",
}

--- The package manager a preset is written for (nil when it is not a Node one)
---@param text string
---@return string?
function M.package_manager(text)
  if text:find("pnpm", 1, true) then
    return "pnpm"
  end
end

--- `pnpm <name>` for npm: a package.json script runs with `npm run`, a tool binary (vitest, drizzle-kit…) with `npx`
local SCRIPTS = {
  dev = true,
  build = true,
  start = true,
  test = true,
  lint = true,
  format = true,
  typecheck = true,
  check = true,
  preview = true,
  e2e = true,
  generate = true,
  clean = true,
}
---@return string
local function npm_run(before, name)
  local script = SCRIPTS[name] or name:find(":", 1, true)
  return before .. (script and "npm run " or "npx ") .. name
end

local PM_RULES = {
  bun = {
    { "pnpm%-lock%.yaml", "bun.lock" },
    { "pnpm install %-%-frozen%-lockfile", "bun install --frozen-lockfile" },
    { "pnpm dlx", "bunx" },
    { "pnpm exec", "bunx" },
    { "pnpm add %-D", "bun add -d" },
    { "pnpm add", "bun add" },
    { "pnpm remove", "bun remove" },
    { "pnpm install", "bun install" },
    { "pnpm run", "bun run" },
    { "([`&;|] ?)pnpm ([%w:_%-]+)", "%1bun run %2" },
    { "%f[%w]pnpm%f[%W]", "Bun" },
  },
  npm = {
    { "pnpm%-lock%.yaml", "package-lock.json" },
    { "pnpm install %-%-frozen%-lockfile", "npm ci" },
    { "pnpm dlx", "npx" },
    { "pnpm exec", "npx" },
    { "pnpm add %-D", "npm install -D" },
    { "pnpm add", "npm install" },
    { "pnpm remove", "npm uninstall" },
    { "pnpm install", "npm install" },
    { "pnpm test", "npm test" },
    { "pnpm run", "npm run" },
    { "([`&;|] ?)pnpm ([%w:_%-]+)", npm_run },
    { "%f[%w]pnpm%f[%W]", "npm" },
  },
}

--- A pnpm preset rewritten for another package manager: commands, lockfile, the Stack row
---@param text string
---@param to "bun"|"npm"|"pnpm"
---@return string
function M.use_package_manager(text, to)
  if to == "pnpm" or not PM_RULES[to] then
    return text
  end
  local out = {}
  for _, line in ipairs(lines_of(text)) do
    if line:match "^|" and row_key(line) == "package" then
      out[#out + 1] = M.PACKAGE_MANAGERS[to]
    else
      for _, rule in ipairs(PM_RULES[to]) do
        line = line:gsub(rule[1], rule[2])
      end
      out[#out + 1] = line
    end
  end
  return join(out)
end

M.LINKS = "Read first"

--- `rows` added at the end of AGENTS.md's "Read first" (the section made after the title when there is none)
---@param lines string[]
---@param rows string[]
---@return string
local function insert_links(lines, rows)
  local first, last = section(lines, M.LINKS)
  if not first then
    local at = #lines + 1 -- after the title and its first paragraph
    for i = 2, #lines do
      if lines[i]:match "^##%s" then
        at = i
        break
      end
    end
    local block = vim.list_extend({ "## " .. M.LINKS, "" }, rows)
    block[#block + 1] = ""
    for k = #block, 1, -1 do
      table.insert(lines, at, block[k])
    end
    return join(lines)
  end
  while last > first and lines[last] == "" do
    last = last - 1
  end
  for k = #rows, 1, -1 do
    table.insert(lines, last + 1, rows[k])
  end
  return join(lines)
end

--- AGENTS.md with a line in "Read first" for each document that is there and is not linked yet. Returns the text and the
--- files it added (empty: nothing to change).
---@param text string
---@param present string[] files that exist (STACK.md, DESIGN.md…)
---@return string, string[]
function M.link_docs(text, present)
  local lines = lines_of(text)
  local added, rows = {}, {}
  for _, d in ipairs(M.DOCS) do
    if d.id ~= "agents" and vim.tbl_contains(present, d.file) and not text:find(d.file, 1, true) then
      added[#added + 1] = d.file
      rows[#rows + 1] = ("- [%s](%s): %s."):format(d.file, d.file, d.about)
    end
  end
  if #added == 0 then
    return join(lines), added
  end
  return insert_links(lines, rows), added
end

--- AGENTS.md with a "Read first" line for one more file (PROGRESS.md, docs/adr/README.md): nil when it is linked already
---@param text string
---@param file string
---@param about string
---@return string?
function M.link_file(text, file, about)
  if text:find(file, 1, true) then
    return nil
  end
  return insert_links(lines_of(text), { ("- [%s](%s): %s."):format(file, file, about) })
end

--- The design preset a description names ("like Linear but warmer" → Linear): the longest name found, as a whole word
---@param description string
---@param list KitPreset[]
---@return KitPreset?
function M.named(description, list)
  local text = " " .. description:lower():gsub("[^%w]+", " ") .. " "
  local best
  for _, p in ipairs(list) do
    for _, name in ipairs { p.name, p.id } do
      local key = " " .. name:lower():gsub("[^%w]+", " "):gsub("^%s+", ""):gsub("%s+$", "") .. " "
      if #key > 3 and text:find(key, 1, true) and (not best or #key > best.len) then
        best = { preset = p, len = #key }
      end
    end
  end
  return best and best.preset
end

return M
