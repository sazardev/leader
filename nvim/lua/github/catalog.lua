-- ── The gh extensions Leader launches ────────────────────────────────────────
-- Pure data and parsers: `lua/github/init.lua` is what runs them. `repo` is what `gh extension install` takes,
-- `label` is the executable gh installs (what `gh extension list` prints) and `cmd` is how it is run.
local M = {}

---@class GhExtension
---@field id string          key of the menu entry
---@field label string       installed command (`gh-dash`), also the name of its terminal
---@field repo string        owner/repo for `gh extension install`
---@field cmd string         how to launch it
---@field desc string        one line, shown in the setup checklist

---@type GhExtension[]
M.EXTENSIONS = {
  {
    id = "dash",
    label = "gh-dash",
    repo = "dlvhdr/gh-dash",
    cmd = "gh dash",
    desc = "PRs and issues in one dashboard (Vim keys, preview, comments)",
  },
  {
    id = "observer",
    label = "gh-observer",
    repo = "fini-net/gh-observer",
    cmd = "gh observer",
    desc = "the current PR's checks live, with queue and run times",
  },
  {
    id = "enhance",
    label = "gh-enhance",
    repo = "dlvhdr/gh-enhance",
    cmd = "gh enhance",
    desc = "Actions runs, jobs and logs; rerun the failed ones",
  },
  {
    id = "news",
    label = "gh-news",
    repo = "chmouel/gh-news",
    cmd = "gh news",
    desc = "GitHub notifications as a TUI (read, mute, snooze, open)",
  },
}

--- The catalog entry with this id. Pure.
---@param id string
---@return GhExtension?
function M.get(id)
  for _, ext in ipairs(M.EXTENSIONS) do
    if ext.id == id then
      return ext
    end
  end
  return nil
end

--- What `gh extension list` says is installed: its repos AND its commands (`gh-dash`), so an extension installed
--- outside this config is recognized by either. Pure.
---@param text string output of `gh extension list`
---@return table<string, boolean>
function M.installed(text)
  local set = {}
  for line in (text .. "\n"):gmatch "([^\n]+)" do
    local repo, command = line:match "^(%S+)%s+(%S+)"
    if repo and repo ~= "REPO" then -- the header, when gh prints one
      set[repo] = true
      set[command] = true
    end
  end
  return set
end

---@param ext GhExtension
---@param set table<string, boolean>
---@return boolean
function M.is_installed(ext, set)
  return set[ext.repo] == true or set[ext.label] == true
end

--- `gh extension install …` for each extension, in order. Pure.
---@param exts GhExtension[]
---@return string[]
function M.install_lines(exts)
  local out = {}
  for _, ext in ipairs(exts) do
    out[#out + 1] = "gh extension install " .. ext.repo
  end
  return out
end

--- How to launch `ext`: plain when installed, install-and-launch when not (so the first press does both). Pure.
---@param ext GhExtension
---@param installed boolean
---@return string
function M.launch(ext, installed)
  if installed then
    return ext.cmd
  end
  return ("gh extension install %s && %s"):format(ext.repo, ext.cmd)
end

--- The setup checklist: missing first (checked), installed after. Pure.
---@param set table<string, boolean>
---@return table[] items, integer missing
function M.items(set)
  local missing, installed = {}, {}
  for _, ext in ipairs(M.EXTENSIONS) do
    local ok = M.is_installed(ext, set)
    local item = {
      label = ext.label,
      desc = (ok and "installed · " or "missing · ") .. ext.desc,
      checked = not ok,
      group = ok and "installed" or "missing",
      ext = ext,
      installed = ok,
    }
    table.insert(ok and installed or missing, item)
  end
  local count = #missing
  return vim.list_extend(missing, installed), count
end

return M
