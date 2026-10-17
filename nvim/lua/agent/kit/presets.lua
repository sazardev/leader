-- ── Project kit presets ──────────────────────────────────────────────────────
-- Plain Markdown files, discovered: drop one in and it shows up in its picker. Three kinds:
--   presets/design/<category>/<name>.md    a whole DESIGN.md (systems: Material 3, Linear…; styles; terminal / TUI)
--   presets/stack/<category>/<name>.md     a whole STACK.md, minus the principles (backend, web, mobile…)
--   presets/principles/<name>.md           one `### Title` section the STACK.md's "Engineering principles" are made of
--   presets/addons/<axis>/<name>.md        a few STACK.md sections merged into a stack (deploy, CI, TypeScript 7…: `compose.merge`)
--   presets/design-addons/<axis>/<name>.md the same for a DESIGN.md (platforms, theme, palette, motion, effects…)
-- The file starts with `<!-- key: value -->` lines, read here and never written to the project:
--   <!-- name: Material 3 -->                 what the picker shows (default: the file name)
--   <!-- desc: Google's adaptive system… -->  one line under it (required)
--   <!-- core: true -->                       principles: checked by default
--   <!-- for: ts web !mobile -->              add-ons: the stacks it fits (tags, `M.tags`; `all` = every one; `!tag` never)
--   <!-- default: backend selfhosted !x -->   add-ons: where it comes checked (the best pick; `M.preselect`); `!tag` never
local M = {}

---@class KitPreset
---@field id string        the file name without .md
---@field name string
---@field desc string
---@field core boolean
---@field fits string[]   add-ons: `for:` tags
---@field defaults string[]  add-ons: `default:` tags
---@field body string      what is written to the project
---@field path string

--- Folders whose label is not just the name capitalized, and the order the pickers show them in (stack, design)
M.DESIGN_CATEGORIES = {
  { id = "systems", label = "Design systems" },
  { id = "styles", label = "Styles" },
  { id = "terminal", label = "Terminal / TUI" },
}
M.CATEGORIES = {
  { id = "backend", label = "Backend" },
  { id = "web", label = "Web" },
  { id = "fullstack", label = "Full stack" },
  { id = "mobile", label = "Mobile" },
  { id = "selfhosted", label = "Self-hosted" },
  { id = "monorepo", label = "Monorepo" },
  { id = "cli-desktop", label = "CLI / desktop" },
  { id = "data-ai", label = "Data / AI" },
  { id = "game", label = "Games" },
  { id = "extension", label = "Extensions / plugins" },
}

---@return string
function M.dir()
  return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/presets"
end

--- The header lines and the body; nil when there is no `desc`
---@param id string
---@param text string
---@param path string?
---@return KitPreset?
function M.parse(id, text, path)
  local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
  local meta, i = {}, 1
  while lines[i] do
    local key, value = lines[i]:match "^<!%-%-%s*([%w_]+):%s*(.-)%s*%-%->%s*$"
    if not key then
      break
    end
    meta[key] = value
    i = i + 1
  end
  while lines[i] == "" do
    i = i + 1
  end
  if not meta.desc or meta.desc == "" then
    return nil
  end
  local body = table.concat(vim.list_slice(lines, i), "\n"):gsub("%s+$", "") .. "\n"
  return {
    id = id,
    name = meta.name or id,
    desc = meta.desc,
    core = meta.core == "true",
    fits = vim.split(meta["for"] or "all", "[%s,]+", { trimempty = true }),
    defaults = vim.split(meta.default or "", "[%s,]+", { trimempty = true }),
    body = body,
    path = path or id,
  }
end

--- Every preset of a folder (relative to presets/), by name
---@param folder string
---@param dir string? tests point it at their own
---@return KitPreset[]
function M.list(folder, dir)
  dir = (dir or M.dir()) .. "/" .. folder
  local out = {}
  for file, kind in vim.fs.dir(dir) do
    if kind == "file" and file:match "%.md$" then
      local f = io.open(dir .. "/" .. file, "r")
      if f then
        local preset = M.parse(file:sub(1, -4), f:read "*a", dir .. "/" .. file)
        f:close()
        out[#out + 1] = preset
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return out
end

--- The categories that have presets: the known ones in their order, then any other folder (label = its name)
---@param dir string?
---@param kind "stack"|"design"? default stack
---@return { id: string, label: string, count: integer }[]
function M.categories(dir, kind)
  kind = kind or "stack"
  local root = (dir or M.dir()) .. "/" .. kind
  local found = {}
  for name, k in vim.fs.dir(root) do
    if k == "directory" then
      found[name] = #M.list(kind .. "/" .. name, dir)
    end
  end
  local out = {}
  for _, c in ipairs(kind == "design" and M.DESIGN_CATEGORIES or M.CATEGORIES) do
    if (found[c.id] or 0) > 0 then
      out[#out + 1] = { id = c.id, label = c.label, count = found[c.id] }
    end
    found[c.id] = nil
  end
  local rest = vim.tbl_keys(found)
  table.sort(rest)
  for _, id in ipairs(rest) do
    if found[id] > 0 then
      out[#out + 1] = { id = id, label = (id:gsub("^%l", string.upper):gsub("-", " ")), count = found[id] }
    end
  end
  return out
end

--- Every preset of a kind, across its categories (each with `category` set)
---@param kind "stack"|"design"
---@param dir string?
---@return KitPreset[]
function M.all(kind, dir)
  local out = {}
  for _, c in ipairs(M.categories(dir, kind)) do
    for _, p in ipairs(M.list(kind .. "/" .. c.id, dir)) do
      p.category = c.id
      out[#out + 1] = p
    end
  end
  return out
end

-- ── Add-ons ──────────────────────────────────────────────────────────────────

--- The customize list's groups, in order. `exclusive`: one of them at most (they replace the same Stack row)
M.AXES = {
  { id = "package-manager", label = "Package manager", exclusive = true },
  { id = "typescript", label = "TypeScript", exclusive = false },
  { id = "lint", label = "Lint and format", exclusive = true },
  { id = "styling", label = "Styling", exclusive = true },
  { id = "deploy", label = "Deploy", exclusive = true },
  { id = "ci", label = "CI", exclusive = true },
  { id = "observability", label = "Observability", exclusive = false },
  { id = "quality", label = "Quality", exclusive = false },
}

--- The DESIGN.md customize list's groups (presets/design-addons/<id>/)
M.DESIGN_AXES = {
  { id = "platforms", label = "Platforms", exclusive = false },
  { id = "theme", label = "Theme", exclusive = true },
  { id = "palette", label = "Palette", exclusive = true },
  { id = "motion", label = "Motion", exclusive = true },
  { id = "effects", label = "Effects", exclusive = false },
  { id = "glyphs", label = "Glyphs", exclusive = true },
  { id = "density", label = "Density", exclusive = true },
  { id = "accessibility", label = "Accessibility", exclusive = false },
  { id = "toolkit", label = "Toolkit", exclusive = true },
}

--- The tags of a design preset: `all`, its id, its category, and `tui` for terminal ones (what design add-ons fit)
---@param preset KitPreset
---@param category string?
---@return table<string, boolean>
function M.design_tags(preset, category)
  local tags = { all = true, [preset.id] = true }
  if category then
    tags[category] = true
  end
  if category == "terminal" then
    tags.tui = true
  else
    tags.gui = true
  end
  return tags
end

--- The design tags plus what the project's STACK.md says (its languages and kind words: `go`, `rust`, `flutter`,
--- `tailwind`…), so a toolkit add-on comes checked for the stack the project uses. Its own `tui`/`gui` and ids win.
---@param tags table<string, boolean>
---@param stack string? the STACK.md text
---@return table<string, boolean>
function M.with_stack(tags, stack)
  if not stack or stack == "" then
    return tags
  end
  local out = vim.deepcopy(tags)
  for tag in pairs(M.tags { id = "", body = stack }) do
    if tag ~= "" and tag ~= "tui" then
      out[tag] = true
    end
  end
  return out
end

--- Tags add-ons ask for (`for: go`, `default: lang:typescript`). Languages come from the Stack table's Language/Runtime rows
--- (the first one is the main language: `lang:<word>`)
--- (prose says "go" or "rust" too often to trust it); a text with no such table (a description) is read word by word.
M.LANG_TAGS = {
  typescript = { "ts", "js" },
  javascript = { "js" },
  node = { "node", "js", "ts" },
  bun = { "bun", "js", "ts" },
  deno = { "js", "ts" },
  go = { "go" },
  rust = { "rust" },
  python = { "python" },
  dart = { "dart" },
  java = { "jvm" },
  kotlin = { "jvm" },
  swift = { "swift" },
  php = { "php" },
  elixir = { "elixir" },
  ruby = { "ruby" },
  ["c#"] = { "dotnet" },
  gdscript = { "gdscript" },
  lua = { "lua" },
}

--- Words that name the kind of thing, wherever they appear in the Summary and Stack sections
M.TAG_WORDS = {
  node = { "node", "node.js" },
  bun = { "bun" },
  pnpm = { "pnpm" },
  flutter = { "flutter" },
  server = { "api", "server", "grpc", "backend" },
  ui = { "react", "vue", "svelte", "solid", "preact", "astro", "lit", "alpine", "htmx", "tailwind", "css" },
  tui = { "tui", "terminal" },
  tailwind = { "tailwind", "tailwindcss" },
}

---@param text string lowercased, padded with spaces, punctuation as spaces
---@param word string
---@return boolean
local function has_word(text, word)
  return text:find(" " .. word .. " ", 1, true) ~= nil
end

--- The tags of a stack preset: its category, its id, `all`, its languages (`go`, `ts`… and `lang:<word>`) and the kind
--- words its Summary/Stack sections use
---@param preset KitPreset
---@param category string?
---@return table<string, boolean>
function M.tags(preset, category)
  local tags = { all = true, [preset.id] = true }
  if category then
    tags[category] = true
  end
  local text = preset.body:match "## Summary(.-)\n## Project layout" or preset.body
  text = " " .. text:lower():gsub("[^%w%._]", " "):gsub("%.%s", "  ") .. " " -- go_router stays one word
  for tag, words in pairs(M.TAG_WORDS) do
    for _, w in ipairs(words) do
      if has_word(text, w) then
        tags[tag] = true
        break
      end
    end
  end
  local from_rows = false
  for row in preset.body:gmatch "\n|[^\n]+" do
    local key, value = row:match "^\n|%s*([^|]-)%s*|%s*([^|]-)%s*|"
    if key and (key:lower():match "^language" or key:lower():match "^runtime") then
      local word = value:gsub("[`*]", ""):match "^(%a+#?)"
      if word then
        word = word:lower()
        if not from_rows then -- the first row is the main language (`lang:`, what defaults follow); the others only fit
          tags["lang:" .. word] = true
        end
        from_rows = true
        for _, t in ipairs(M.LANG_TAGS[word] or {}) do
          tags[t] = true
        end
      end
    end
  end
  if not from_rows and tags.flutter then
    tags.dart, tags["lang:dart"] = true, true
  end
  if not from_rows and not preset.body:find("\n## Stack", 1, true) then -- a description: its words name the languages
    for word, list in pairs(M.LANG_TAGS) do
      if has_word(text, word) then
        tags["lang:" .. word] = true
        for _, t in ipairs(list) do
          tags[t] = true
        end
      end
    end
  end
  return tags
end

---@class KitAddon: KitPreset
---@field axis string
---@field group string   the axis label

--- The add-ons that fit those tags, axis by axis (the order of M.AXES, then any other axis folder)
---@param tags table<string, boolean>
---@param dir string?
---@param kind "stack"|"design"? default stack (presets/addons); design = presets/design-addons
---@return KitAddon[]
function M.addons(tags, dir, kind)
  local folder = kind == "design" and "design-addons" or "addons"
  local root = (dir or M.dir()) .. "/" .. folder
  local axes = vim.deepcopy(kind == "design" and M.DESIGN_AXES or M.AXES)
  local known = {}
  for _, a in ipairs(axes) do
    known[a.id] = true
  end
  local extra = {}
  for name, kind in vim.fs.dir(root) do
    if kind == "directory" and not known[name] then
      extra[#extra + 1] = name
    end
  end
  table.sort(extra)
  for _, name in ipairs(extra) do
    axes[#axes + 1] = { id = name, label = (name:gsub("^%l", string.upper):gsub("-", " ")), exclusive = false }
  end
  local out = {}
  for _, axis in ipairs(axes) do
    for _, p in ipairs(M.list(folder .. "/" .. axis.id, dir)) do
      local fits = vim.iter(p.fits):any(function(t)
        return tags[t] == true
      end) and not vim.iter(p.fits):any(function(t)
        return t:sub(1, 1) == "!" and tags[t:sub(2)] == true -- `!mobile`: never offered to those
      end)
      if fits then
        p.axis, p.group = axis.id, axis.label
        out[#out + 1] = p
      end
    end
  end
  return out
end

--- How well an add-on's `default:` tags name this stack: its id 3, a word of it (go, ts, flutter…) 2, its category 1, `all` 0;
--- nil when none matches
---@param addon KitAddon
---@param tags table<string, boolean>
---@param id string the stack's id
---@param category string?
---@return integer?
local function score(addon, tags, id, category)
  local best
  for _, t in ipairs(addon.defaults) do
    if t:sub(1, 1) == "!" and tags[t:sub(2)] then -- `!lit`: never the default for that stack
      return nil
    end
  end
  for _, t in ipairs(addon.defaults) do
    if tags[t] then
      local s = (t == id and 3) or (t == "all" and 0) or (t == category and 1) or 2
      best = math.max(best or -1, s)
    end
  end
  return best
end

--- The add-ons that come checked: in a one-of group the best match (the most specific `default:`), elsewhere every match
---@param addons KitAddon[]
---@param tags table<string, boolean>
---@param id string
---@param category string?
---@return table<KitAddon, boolean>
function M.preselect(addons, tags, id, category)
  local out, best = {}, {}
  for _, a in ipairs(addons) do
    local s = score(a, tags, id, category)
    if s then
      if M.exclusive(a.group) then
        if not best[a.group] or s > best[a.group].score then
          best[a.group] = { addon = a, score = s }
        end
      else
        out[a] = true
      end
    end
  end
  for _, b in pairs(best) do
    out[b.addon] = true
  end
  return out
end

--- Is this axis one-of?
---@param label string
---@return boolean
function M.exclusive(label)
  for _, a in ipairs(vim.list_extend(vim.deepcopy(M.AXES), M.DESIGN_AXES)) do
    if a.label == label then
      return a.exclusive
    end
  end
  return false
end

return M
