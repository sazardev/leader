-- ── Recipes (<leader>aSr): prefab tasks, built on the project as it is ───────
-- A recipe is a plain Markdown file in presets/recipes/<group>/<name>.md (auto-discovered), with the presets' header
-- plus the values it asks for:
--   <!-- name: Screen with a Riverpod provider -->
--   <!-- desc: a screen, its Notifier, its route and a widget test -->
--   <!-- for: flutter -->                       (STACK.md's tags, like the add-ons; `go+server` = both, `go+!server`, `!tui` = never)
--   <!-- input: name | Name of the screen (e.g. Profile) -->   (one line per value; the first names the build)
-- and a body that says what to make (## Make, ## Rules, ## Tests) with `{{name}}` and its spellings: `{{name_snake}}`
-- (user_profile), `{{name_camel}}` (userProfile), `{{name_pascal}}` (UserProfile), `{{name_kebab}}` (user-profile).
-- Picking one asks its values, fills the body and opens the build (scope `recipe`): plan → review (the confirmation) →
-- write → check → fix, where STACK.md and the existing code put each kind of file. The text work is pure (tested in
-- test-kit-feature.lua: every recipe parses, fits some stack and fills every placeholder).
local M = {}

---@class KitRecipe: KitPreset
---@field group string
---@field inputs { key: string, question: string }[]

--- A recipe from its file; nil when it has no `desc` or asks for nothing
---@param id string "flutter/screen-riverpod"
---@param text string
---@param path string?
---@return KitRecipe?
function M.parse(id, text, path)
  local preset = require("agent.kit.presets").parse(id, text, path)
  if not preset then
    return nil
  end
  local inputs = {}
  for line in text:gmatch "[^\n]+" do
    if not line:match "^<!%-%-" then
      break
    end
    local key, question = line:match "^<!%-%-%s*input:%s*([%w_]+)%s*|%s*(.-)%s*%-%->%s*$"
    if key then
      inputs[#inputs + 1] = { key = key, question = question }
    end
  end
  if #inputs == 0 then
    return nil
  end
  local recipe = preset --[[@as KitRecipe]]
  recipe.group = id:match "^([^/]+)/" or "general"
  recipe.inputs = inputs
  return recipe
end

--- Every recipe, group by group
---@param dir string? tests point it at their own
---@return KitRecipe[]
function M.all(dir)
  local root = (dir or require("agent.kit.presets").dir()) .. "/recipes"
  local out = {}
  local groups = {}
  for name, kind in vim.fs.dir(root) do
    if kind == "directory" then
      groups[#groups + 1] = name
    end
  end
  table.sort(groups)
  for _, g in ipairs(groups) do
    local files = {}
    for file, kind in vim.fs.dir(root .. "/" .. g) do
      if kind == "file" and file:match "%.md$" then
        files[#files + 1] = file
      end
    end
    table.sort(files)
    for _, file in ipairs(files) do
      local path = root .. "/" .. g .. "/" .. file
      local text = require("utils.project").read(path) or ""
      local recipe = M.parse(g .. "/" .. file:sub(1, -4), text, path)
      if recipe then
        out[#out + 1] = recipe
      end
    end
  end
  return out
end

--- The tags of the project's STACK.md (the same words the add-ons are matched against)
---@param stack string
---@return table<string, boolean>
function M.tags(stack)
  return require("agent.kit.presets").tags { id = "project", body = stack }
end

--- Does a recipe fit those tags? (`for:` any of them, `go+server` = both; `!tag` never)
---@param recipe KitRecipe
---@param tags table<string, boolean>
---@return boolean
function M.fits(recipe, tags)
  local yes = vim.iter(recipe.fits):any(function(t)
    return t:sub(1, 1) ~= "!"
      and vim.iter(vim.split(t, "+", { plain = true })):all(function(part)
        if part:sub(1, 1) == "!" then -- `go+!server`: a Go project that is not a server
          return tags[part:sub(2)] ~= true
        end
        return tags[part] == true
      end)
  end)
  local no = vim.iter(recipe.fits):any(function(t)
    return t:sub(1, 1) == "!" and tags[t:sub(2)] == true
  end)
  return yes and not no
end

--- The words of a value: "user profile", "UserProfile", "user_profile" → { "user", "profile" }
---@param value string
---@return string[]
local function words(value)
  local spaced = value:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gsub("[^%w]+", " ")
  local out = {}
  for w in spaced:gmatch "%S+" do
    out[#out + 1] = w:lower()
  end
  return out
end

--- A value in every spelling a recipe uses (pure)
---@param value string
---@return { snake: string, camel: string, pascal: string, kebab: string }
function M.spellings(value)
  local w = words(value)
  local pascal = table.concat(vim.tbl_map(function(x)
    return x:sub(1, 1):upper() .. x:sub(2)
  end, w))
  return {
    snake = table.concat(w, "_"),
    kebab = table.concat(w, "-"),
    pascal = pascal,
    camel = pascal:sub(1, 1):lower() .. pascal:sub(2),
  }
end

--- The body with every `{{key}}` and its spellings filled (pure); what is left unfilled is listed
---@param body string
---@param values table<string, string>
---@return string text, string[] unfilled
function M.fill(body, values)
  local text = body
  for key, value in pairs(values) do
    local s = M.spellings(value)
    text = text:gsub("{{" .. key .. "}}", (value:gsub("%%", "%%%%")))
    for kind, v in pairs(s) do
      text = text:gsub("{{" .. key .. "_" .. kind .. "}}", (v:gsub("%%", "%%%%")))
    end
  end
  local left = {}
  for name in text:gmatch "{{([%w_]+)}}" do
    if not vim.tbl_contains(left, name) then
      left[#left + 1] = name
    end
  end
  return text, left
end

--- The build task of a recipe with its values
---@param recipe KitRecipe
---@param values table<string, string>
---@return BuildTask
function M.task(recipe, values)
  local first = values[recipe.inputs[1].key] or ""
  return {
    id = recipe.id .. ":" .. M.spellings(first).kebab,
    title = ("%s · %s"):format(recipe.name, first),
    text = (M.fill(recipe.body, values)),
  }
end

--- Asks the recipe's values one by one, then opens its build
---@param recipe KitRecipe
local function ask(recipe)
  local values, i = {}, 0
  local function next_value()
    i = i + 1
    local input = recipe.inputs[i]
    if not input then
      return require("agent.kit.build").open("recipe", M.task(recipe, values))
    end
    local modal = require "utils.modal"
    modal.input({ { { input.question, modal.hl.muted } } }, { title = recipe.name, confirm = "Next" }, function(text)
      if text == "" then
        return require("utils.log").info "Setup: the recipe needs that value"
      end
      values[input.key] = text
      next_value()
    end)
  end
  next_value()
end

M.start = ask

--- <leader>aSr: the recipes that fit the project's STACK.md (all of them when none does), with their file as preview
function M.open()
  local log = require "utils.log"
  local root = require("agent.kit.snapshot").root()
  local stack = require("utils.project").read(root .. "/STACK.md")
  if not stack then
    return log.error "Setup: a recipe follows STACK.md: write it first (<leader>aSt)"
  end
  local tags = M.tags(stack)
  local all = M.all()
  local list = vim.tbl_filter(function(r)
    return M.fits(r, tags)
  end, all)
  local title = "Recipes for this stack"
  if #list == 0 then
    list, title = all, "Recipes · none fits STACK.md: all of them"
  end
  local items = vim.tbl_map(function(r)
    return { label = r.name, desc = r.desc, path = r.path, search = r.group .. " " .. r.id, value = r }
  end, list)
  require("tasks.picker").choose(items, { title = title, preview = true, width = 34 }, ask)
end

return M
