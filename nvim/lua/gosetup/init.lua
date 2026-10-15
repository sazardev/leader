-- ── Go project setup (<leader>gS) ────────────────────────────────────────────
-- The config files a Go project usually wants, one key each: golangci-lint, Air, a Dockerfile and its .dockerignore, a CI workflow,
-- git hooks, .editorconfig. Presets are plain files (`presets/<topic>/<variant>.<ext>`, `presets/init.lua`) filled in from the
-- project (`vars.lua`: module path, Go version, where `main` is). 0 tokens, nothing resident. It never overwrites: a file that is
-- already there is opened, and a misnamed golangci config (`.golangcli.yml`) is offered a rename.
local log = require "utils.log"
local presets = require "gosetup.presets"
local vars = require "gosetup.vars"

local M = {}

---@class SetupTopic
---@field id string
---@field key string              after `<leader>gS`
---@field label string
---@field folder string           in presets/
---@field default string          variant used when several topics are created at once
---@field core boolean?           checked by default in the "several" list
---@field alts string[]?          other names that count as the file being there
---@field misnamed string[]?      names that look right and are not read by the tool

---@type SetupTopic[]
M.TOPICS = {
  {
    id = "golangci",
    key = "l",
    label = "golangci-lint config",
    folder = "golangci",
    default = "standard",
    core = true,
    alts = { ".golangci.yaml", ".golangci.toml", ".golangci.json" },
    misnamed = {
      ".golangcli.yml",
      ".golangcli.yaml",
      ".golangci-lint.yml",
      ".golangci-lint.yaml",
      ".golang-ci.yml",
      ".golang-ci.yaml",
    },
  },
  { id = "air", key = "a", label = "Air live reload (.air.toml)", folder = "air", default = "api", core = true },
  {
    id = "docker",
    key = "d",
    label = "Dockerfile",
    folder = "docker",
    default = "alpine",
    alts = { "dockerfile", "Dockerfile.prod" },
  },
  { id = "dockerignore", key = "i", label = ".dockerignore", folder = "dockerignore", default = "go" },
  {
    id = "ci",
    key = "c",
    label = "GitHub Actions CI",
    folder = "ci",
    default = "github",
    alts = { ".github/workflows/ci.yaml", ".github/workflows/go.yml" },
  },
  {
    id = "hooks",
    key = "h",
    label = "git hooks (lefthook)",
    folder = "hooks",
    default = "lefthook",
    alts = { "lefthook.yaml", ".lefthook.yml", ".lefthook.yaml" },
  },
  { id = "editorconfig", key = "e", label = ".editorconfig", folder = "editorconfig", default = "go", core = true },
}

---@param id string
---@return SetupTopic?
function M.topic(id)
  for _, t in ipairs(M.TOPICS) do
    if t.id == id then
      return t
    end
  end
end

--- The module being set up: the nearest go.mod's folder, else the git root, else the folder itself
---@param dir string?
---@return string
function M.root(dir)
  dir = dir or require("utils.project").file_dir()
  local gomod = vim.fs.find("go.mod", { path = dir, upward = true })[1]
  return gomod and vim.fs.dirname(gomod) or vim.fs.root(dir, ".git") or dir
end

---@param path string
---@return boolean
local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

---@class SetupState
---@field kind "absent"|"exists"|"misnamed"
---@field path string?  the file found

--- Whether the topic's file is there, is there under a name the tool ignores, or is missing
---@param root string
---@param topic SetupTopic
---@param target string
---@return SetupState
function M.state(root, topic, target)
  for _, name in ipairs(vim.list_extend({ target }, topic.alts or {})) do
    if exists(root .. "/" .. name) then
      return { kind = "exists", path = root .. "/" .. name }
    end
  end
  for _, name in ipairs(topic.misnamed or {}) do
    if exists(root .. "/" .. name) then
      return { kind = "misnamed", path = root .. "/" .. name }
    end
  end
  return { kind = "absent" }
end

--- The file as it will be written, with what the project says filled in
---@param root string
---@param variant SetupVariant
---@param v SetupVars?
---@return string text, string[] unknown
function M.render(root, variant, v)
  local text, unknown = vars.render(variant.body, v or vars.collect(root))
  return (text:gsub("%s+$", "")) .. "\n", unknown
end

--- Writes the variant under `root`; never overwrites
---@param root string
---@param variant SetupVariant
---@return string? path, string? reason
function M.write(root, variant)
  local path = root .. "/" .. variant.target
  if exists(path) then
    return nil, variant.target .. " is already there"
  end
  local text, unknown = M.render(root, variant)
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

--- Major version of golangci-lint from `--version`'s text (`version v1.64.8` or `version 2.13.2`)
---@param text string
---@return integer?
function M.golangci_major(text)
  local n = text:match "version v?(%d+)%."
  return n and tonumber(n) or nil
end

--- What is worth knowing once a file exists
---@param topic SetupTopic
---@param root string
local function hint(topic, root)
  if topic.id == "golangci" then
    if vim.fn.executable "golangci-lint" ~= 1 then
      return log.info "Setup: golangci-lint is not installed (:Mason, or go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest)"
    end
    pcall(vim.system, { "golangci-lint", "--version" }, { text = true }, function(res)
      if M.golangci_major(res.stdout or "") == 1 then
        vim.schedule(function()
          log.warn 'Setup: this golangci-lint is v1 and the config is v2 (version: "2"): install v2 or it refuses to start'
        end)
      end
    end)
  elseif topic.id == "air" and vim.fn.executable "air" ~= 1 then
    log.info "Setup: air is not installed (go install github.com/air-verse/air@latest), then `air` in the project"
  elseif topic.id == "hooks" then
    log.info(
      vim.fn.executable "lefthook" == 1 and "Setup: run `lefthook install` once to activate the hooks"
        or "Setup: lefthook is not installed (go install github.com/evilmartians/lefthook@latest), then `lefthook install`"
    )
  elseif topic.id == "docker" then
    log.info(("Setup: docker build -t %s ."):format(vars.collect(root).binary))
  end
end

--- Opens a file that is already there
---@param path string
---@param root string
local function open_existing(path, root)
  log.info(("Setup: %s is already there, opened it"):format(path:sub(#root + 2)))
  vim.cmd.edit(vim.fn.fnameescape(path))
end

--- Renames a file that has the wrong name, the way the file operations do (buffers and servers follow)
---@param old string
---@param new string
function M.rename(old, new)
  local ops, buffers = require "files.ops", require "files.buffers"
  buffers.lsp_will_rename(old, new)
  local ok, why = ops.rename(old, new)
  if not ok then
    return log.warn("Setup: " .. (why or "could not rename"))
  end
  buffers.renamed(old, new)
  buffers.lsp_did_rename(old, new)
  buffers.refresh_tree()
  log.info(("Setup: renamed %s to %s"):format(vim.fs.basename(old), vim.fs.basename(new)))
end

--- Renders every variant into a scratch folder, so the picker's preview shows the file as it will be written
---@param root string
---@param list SetupVariant[]
---@return table<string, string>
local function previews(root, list)
  local v = vars.collect(root)
  local base = vim.fn.stdpath "cache" .. "/gosetup-preview"
  local out = {}
  for _, variant in ipairs(list) do
    local path = ("%s/%s/%s"):format(base, variant.name, vim.fs.basename(variant.target))
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = io.open(path, "w")
    if f then
      f:write((M.render(root, variant, v)))
      f:close()
      out[variant.name] = path
    end
  end
  return out
end

--- Creates one topic's file: a variant picker when there are several
---@param id string
---@param dir string? where to look for the module (default: the current file's)
function M.create(id, dir)
  local topic = M.topic(id)
  local list = topic and presets.variants(topic.folder)
  if not topic or #list == 0 then
    return log.warn("Setup: no presets for " .. tostring(id))
  end
  local root = M.root(dir)
  local state = M.state(root, topic, list[1].target)
  if state.kind == "exists" then
    return open_existing(state.path, root)
  end

  local function done(variant)
    local path, why = M.write(root, variant)
    if not path then
      return log.warn("Setup: " .. why)
    end
    vim.cmd.edit(vim.fn.fnameescape(path))
    log.info(("Setup: created %s (%s)"):format(variant.target, variant.name))
    hint(topic, root)
  end
  local function choose()
    if #list == 1 then
      return done(list[1])
    end
    local shown = previews(root, list)
    require("tasks.picker").choose(
      vim.tbl_map(function(variant)
        return { label = variant.name, desc = variant.desc, path = shown[variant.name], value = variant }
      end, list),
      { title = topic.label .. " for " .. vim.fn.fnamemodify(root, ":~"), preview = true },
      done
    )
  end

  if state.kind == "misnamed" then
    local modal = require "utils.modal"
    local want = list[1].target
    return modal.confirm({
      { { vim.fs.basename(state.path), modal.hl.file }, { " is not read by the tool", modal.hl.muted } },
      { { "It looks for ", modal.hl.muted }, { want, modal.hl.mark } },
      "",
      { { "Rename keeps what is written in it", modal.hl.muted } },
    }, { title = "Misnamed " .. topic.label, confirm = "Rename" }, function()
      M.rename(state.path, root .. "/" .. want)
    end)
  end
  choose()
end

--- Several at once: a checklist of every topic, each created with its default variant
---@param dir string?
function M.pick(dir)
  local root = M.root(dir)
  local items, entries = {}, {}
  for _, topic in ipairs(M.TOPICS) do
    local list = presets.variants(topic.folder)
    local variant
    for _, v in ipairs(list) do
      variant = variant or v
      if v.name == topic.default then
        variant = v
      end
    end
    if variant then
      local state = M.state(root, topic, variant.target)
      local desc = ({
        exists = "already there: " .. (state.path and state.path:sub(#root + 2) or ""),
        misnamed = "found " .. (state.path and vim.fs.basename(state.path) or "") .. " (wrong name: use its own key)",
        absent = variant.target .. " · " .. variant.name,
      })[state.kind]
      items[#items + 1] = { label = topic.label, desc = desc, checked = state.kind == "absent" and topic.core or false }
      entries[#entries + 1] = { topic = topic, variant = variant, state = state }
    end
  end
  local modal = require "utils.modal"
  modal.checklist(items, {
    title = "Go project setup",
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
      if e.state.kind ~= "absent" then
        log.info(
          ("Setup: %s: skipped, %s"):format(
            e.topic.label,
            e.state.kind == "exists" and "already there" or "misnamed file found"
          )
        )
      else
        local path, why = M.write(root, e.variant)
        if path then
          made[#made + 1] = e.variant.target
          first = first or path
          hint(e.topic, root)
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

--- The `<leader>gS` entries of the Go menu: { key, desc, fn }
---@return table[]
function M.maps()
  local out = {}
  for _, topic in ipairs(M.TOPICS) do
    out[#out + 1] = {
      "S" .. topic.key,
      "setup " .. topic.label,
      function()
        M.create(topic.id)
      end,
    }
  end
  vim.list_extend(out, {
    {
      "Sp",
      "setup several files",
      function()
        M.pick()
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
