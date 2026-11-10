-- ── GitHub CLI: the TUIs (gh-dash, gh-observer, gh-enhance, gh-news) and the core commands ───────────────────────
-- The `<leader>Gh` menu. Extensions are never installed silently: the first launch of a missing one asks, installing
-- and launching in the same terminal command. Everything goes through the integrated terminal (credentials and the
-- TUIs need a TTY); `utils/terminal.tui` only focuses a TUI that is already running instead of typing into it.
-- `catalog.lua` holds the data and the pure parsers.
local catalog = require "github.catalog"
local git = require "commit.git"
local log = require "utils.log"
local modal = require "utils.modal"
local terminal = require "utils.terminal"
local M = {}

---@return boolean
local function has_gh()
  if vim.fn.executable "gh" == 1 then
    return true
  end
  log.warn "GitHub: `gh` is not installed (https://cli.github.com)"
  return false
end

---@return boolean
local function authenticated()
  if vim.system({ "gh", "auth", "status" }, { text = true }):wait().code == 0 then
    return true
  end
  log.warn "GitHub: not logged in (run `gh auth login`, or <leader>GhA)"
  return false
end

--- Repos and commands `gh extension list` reports. Exposed for tests.
---@return table<string, boolean>
function M.installed()
  local res = vim.system({ "gh", "extension", "list" }, { text = true }):wait()
  return catalog.installed(res.code == 0 and (res.stdout or "") or "")
end

--- The repository root, warning when there is none (gh-dash and the notifications work anywhere).
---@return string?
local function repo_root()
  local root = git.root()
  if not root then
    log.warn "GitHub: this one needs a repository (gh-dash and gh-news work anywhere)"
  end
  return root
end

--- Run `cmd` in the shared command terminal, from `dir` (defaults to the cwd). Exposed for tests.
---@param cmd string
---@param dir string?
function M.run(cmd, dir)
  if not has_gh() then
    return
  end
  terminal.run(cmd, dir or vim.fn.getcwd())
end

--- A core gh command that only makes sense inside a repository (`gh pr view`, `gh browse`, `gh run list`…).
---@param cmd string
function M.run_in_repo(cmd)
  local root = repo_root()
  if root then
    M.run(cmd, root)
  end
end

--- Launch extension `id`: focus its terminal when it is already running, start it otherwise, and offer to install it
--- (the exact command is shown, nothing runs before the confirmation) when it is missing.
---@param id string
function M.launch(id)
  local ext = catalog.get(id)
  if not ext or not has_gh() or not authenticated() then
    return
  end
  local cwd = vim.fn.getcwd()
  if catalog.is_installed(ext, M.installed()) then
    return terminal.tui(ext.label, ext.cmd, cwd)
  end
  modal.confirm({
    { { ("%s is not installed."):format(ext.label), modal.hl.key } },
    { { ext.desc, modal.hl.muted } },
    { { ("It will run: gh extension install %s && %s"):format(ext.repo, ext.cmd), modal.hl.file } },
  }, { title = ext.label, confirm = "Install" }, function()
    terminal.tui(ext.label, catalog.launch(ext, false), cwd)
  end)
end

--- `gh` command (the shared terminal) for the `Octo` command of octo.nvim.
---@param args string
function M.octo(args)
  if not has_gh() or not authenticated() then
    return
  end
  if vim.fn.exists ":Octo" ~= 2 then
    log.warn "GitHub: octo.nvim is not installed yet (restart, or run `:Lazy sync`)"
    return
  end
  if not repo_root() then
    return
  end
  local ok, err = pcall(vim.cmd, "Octo " .. args)
  if not ok then
    log.warn("GitHub: " .. tostring(err))
  end
end

--- The extensions setup: a checklist of what is missing (checked) and what is installed; Enter installs the checked
--- ones in the terminal. Nothing runs before that.
function M.setup()
  if not has_gh() then
    return
  end
  local items, missing = catalog.items(M.installed())
  if missing == 0 then
    return log.info "GitHub: every extension in the menu is installed"
  end
  local intro = {
    { { "gh extension install … (shared command terminal)", modal.hl.muted } },
  }
  if not authenticated() then
    intro[#intro + 1] = { { "Not logged in: <leader>GhA runs `gh auth login` first.", modal.hl.warn } }
  end
  intro[#intro + 1] = { { "Nothing runs until you press Enter; Esc cancels.", modal.hl.muted } }
  modal.checklist(items, {
    title = "gh extensions",
    intro = intro,
    footer = "Space/x toggle · Enter install the checked ones · Esc cancel",
  }, function(chosen)
    local exts = {}
    for _, i in ipairs(chosen) do
      if not items[i].installed then
        exts[#exts + 1] = items[i].ext
      end
    end
    if #exts == 0 then
      return log.info "GitHub: nothing to install"
    end
    terminal.run(table.concat(catalog.install_lines(exts), " && "), vim.fn.getcwd())
  end)
end

return M
