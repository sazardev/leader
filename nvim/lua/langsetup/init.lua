-- ── Project setup per language (<leader>tS, pS, rS, iS) ──────────────────────
-- The config files a project of that language usually wants, one key each, like Go's (<leader>gS, lua/gosetup/): a
-- language is a file in `langs/<lang>.lua` (its topics, its root, what it reads from the project), its presets are
-- plain files in `presets/<lang>/<topic>/<variant>.<ext>`:
--   # what it is, in one line        <- line 1 (`#` or `//`): the file's first comment (not into JSON or .nvmrc)
--   # target: tsconfig.json          <- line 2: where it goes, relative to the project root (not written)
--   …the file, with `{{name}}`-style placeholders the language fills from the project
-- Never overwrites: a file that is there is opened. The pure parts (parse, render) are tested in test-langs.lua.
local log = require "utils.log"

local M = {}

M.LANGS = { "typescript", "python", "rust", "swift" }

---@class LangSetupVariant
---@field name string
---@field desc string
---@field target string
---@field body string
---@field path string

---@class LangSetupTopic
---@field id string
---@field key string      after `S`
---@field label string
---@field default string  the variant used when several topics are created at once
---@field core boolean?   checked by default in the "several" list
---@field alts string[]?  other names that count as the file being there

---@class LangSetupLang
---@field name string
---@field root fun(dir: string): string
---@field vars fun(root: string): table<string, string>
---@field topics LangSetupTopic[]
---@field hint (fun(topic: LangSetupTopic, root: string): string?)?

---@return string
function M.dir()
  return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/presets"
end

-- files that take no comment: the description is not written into them
local BARE = { [".nvmrc"] = true, [".node-version"] = true, [".python-version"] = true, [".swift-format"] = true }

--- Does this target take no comments? (JSON, version files)
---@param target string
---@return boolean
function M.bare(target)
  return target:match "%.json$" ~= nil or BARE[vim.fs.basename(target)] == true
end

--- A preset from its text; nil when its first two lines are not the description and the target
---@param name string
---@param text string
---@param path string?
---@return LangSetupVariant?
function M.parse(name, text, path)
  local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
  local mark, desc = (lines[1] or ""):match "^(#)%s*(.-)%s*$"
  if not mark then
    mark, desc = (lines[1] or ""):match "^(//)%s*(.-)%s*$"
  end
  local target = (lines[2] or ""):match("^" .. vim.pesc(mark or "#") .. "%s*target:%s*(%S+)%s*$")
  if not desc or desc == "" or not target then
    return nil
  end
  local rest = M.bare(target) and {} or { lines[1] }
  vim.list_extend(rest, lines, 3)
  return { name = name, desc = desc, target = target, body = table.concat(rest, "\n"), path = path or name }
end

--- The variants of a topic, by name
---@param lang string
---@param topic string
---@param dir string?
---@return LangSetupVariant[]
function M.variants(lang, topic, dir)
  local folder = (dir or M.dir()) .. "/" .. lang .. "/" .. topic
  local out = {}
  for file, kind in vim.fs.dir(folder) do
    if kind == "file" then
      local text = require("utils.project").read(folder .. "/" .. file) or ""
      local v = M.parse(file:match "^(.-)%.[^.]+$" or file, text, folder .. "/" .. file)
      if v then
        out[#out + 1] = v
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- The file as it will be written (pure): placeholders filled; the ones the values lack are listed
---@param body string
---@param vars table<string, string>
---@return string text, string[] unknown
function M.render(body, vars)
  local unknown = {}
  local text = body:gsub("{{([%w_]+)}}", function(key)
    if vars[key] == nil then
      unknown[#unknown + 1] = key
      return "{{" .. key .. "}}"
    end
    return vars[key]
  end)
  return (text:gsub("%s+$", "")) .. "\n", unknown
end

---@param lang string
---@return LangSetupLang
function M.lang(lang)
  return require("langsetup.langs." .. lang)
end

---@param path string
---@return boolean
local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

--- Where the topic's file already is, if anywhere
---@param root string
---@param topic LangSetupTopic
---@param target string
---@return string?
local function there(root, topic, target)
  for _, name in ipairs(vim.list_extend({ target }, topic.alts or {})) do
    if exists(root .. "/" .. name) then
      return root .. "/" .. name
    end
  end
end

--- Writes a variant under `root`; never overwrites
---@param root string
---@param variant LangSetupVariant
---@param vars table<string, string>
---@return string? path, string? reason
function M.write(root, variant, vars)
  local path = root .. "/" .. variant.target
  if exists(path) then
    return nil, variant.target .. " is already there"
  end
  local text, unknown = M.render(variant.body, vars)
  if #unknown > 0 then
    return nil, "unknown placeholder {{" .. unknown[1] .. "}} in the preset"
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(text)
  f:close()
  return path
end

--- Every variant rendered into a scratch folder, so the picker's preview shows the file as it will be written
---@param list LangSetupVariant[]
---@param vars table<string, string>
---@return table<string, string>
local function previews(list, vars)
  local base = vim.fn.stdpath "cache" .. "/langsetup-preview"
  local out = {}
  for _, v in ipairs(list) do
    local path = ("%s/%s/%s"):format(base, v.name, vim.fs.basename(v.target))
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = io.open(path, "w")
    if f then
      f:write((M.render(v.body, vars)))
      f:close()
      out[v.name] = path
    end
  end
  return out
end

---@param l LangSetupLang
---@param topic LangSetupTopic
---@param root string
local function hint(l, topic, root)
  local text = l.hint and l.hint(topic, root)
  if text then
    log.info("Setup: " .. text)
  end
end

--- One topic's file: a variant picker when there are several
---@param lang string
---@param id string
function M.create(lang, id)
  local l = M.lang(lang)
  local topic = vim.iter(l.topics):find(function(t)
    return t.id == id
  end)
  local list = topic and M.variants(lang, topic.id) or {}
  if not topic or #list == 0 then
    return log.warn("Setup: no presets for " .. tostring(id))
  end
  local root = l.root(require("utils.project").file_dir())
  local found = there(root, topic, list[1].target)
  if found then
    log.info(("Setup: %s is already there, opened it"):format(found:sub(#root + 2)))
    return vim.cmd.edit(vim.fn.fnameescape(found))
  end
  local vars = l.vars(root)
  local function done(variant)
    local path, why = M.write(root, variant, vars)
    if not path then
      return log.warn("Setup: " .. why)
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
    log.info(("Setup: created %s (%s)"):format(variant.target, variant.name))
    hint(l, topic, root)
  end
  if #list == 1 then
    return done(list[1])
  end
  local shown = previews(list, vars)
  require("tasks.picker").choose(
    vim.tbl_map(function(v)
      return { label = v.name, desc = v.desc, path = shown[v.name], value = v }
    end, list),
    { title = topic.label .. " for " .. vim.fn.fnamemodify(root, ":~"), preview = true },
    done
  )
end

--- Several at once: a checklist of every topic, each with its default variant
---@param lang string
function M.pick(lang)
  local l = M.lang(lang)
  local root = l.root(require("utils.project").file_dir())
  local vars = l.vars(root)
  local items, entries = {}, {}
  for _, topic in ipairs(l.topics) do
    local list = M.variants(lang, topic.id)
    local variant = vim.iter(list):find(function(v)
      return v.name == topic.default
    end) or list[1]
    if variant then
      local found = there(root, topic, variant.target)
      items[#items + 1] = {
        label = topic.label,
        desc = found and ("already there: " .. found:sub(#root + 2)) or (variant.target .. " · " .. variant.name),
        checked = not found and topic.core or false,
      }
      entries[#entries + 1] = { topic = topic, variant = variant, found = found }
    end
  end
  local modal = require "utils.modal"
  modal.checklist(items, {
    title = l.name .. " project setup",
    intro = {
      { { vim.fn.fnamemodify(root, ":~"), modal.hl.folder } },
      { { "Creates what is missing, never overwrites.", modal.hl.muted } },
      "",
    },
    confirm = "Create",
    footer = "Space toggle · a all",
  }, function(indexes)
    local made, first = {}, nil
    for _, i in ipairs(indexes) do
      local e = entries[i]
      if e.found then
        log.info(("Setup: %s: skipped, already there"):format(e.topic.label))
      else
        local path, why = M.write(root, e.variant, vars)
        if path then
          made[#made + 1] = e.variant.target
          first = first or path
          hint(l, e.topic, root)
        else
          log.warn("Setup: " .. why)
        end
      end
    end
    if first then
      vim.cmd.edit(vim.fn.fnameescape(first))
      log.info("Setup: created " .. table.concat(made, ", "))
    end
  end)
end

--- The `S…` entries of a language menu: one per topic, several at once, the Makefile and .gitignore
---@param lang string
---@return table[]
function M.maps(lang)
  local out = {}
  for _, topic in ipairs(M.lang(lang).topics) do
    out[#out + 1] = {
      "S" .. topic.key,
      "setup " .. topic.label,
      function()
        M.create(lang, topic.id)
      end,
    }
  end
  vim.list_extend(out, {
    {
      "Sp",
      "setup several files",
      function()
        M.pick(lang)
      end,
    },
    {
      "Sm",
      "setup Makefile",
      function()
        require("tasks").create()
      end,
    },
    {
      "Sg",
      "setup gitignore",
      function()
        require("gitignore").open()
      end,
    },
  })
  return out
end

return M
