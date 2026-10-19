-- ── Merge conflicts, with the agent ──────────────────────────────────────────
-- git-conflict.nvim already chooses ours / theirs / both and moves between conflicts (the Git menu's `o T B N n p l`). This
-- adds what it cannot do: resolve the ones that need no model for free (both sides made the same change, or only one changed
-- anything), have the agent merge the intent of both sides (each conflict is one proposal with the usual inline diff and
-- the proposal queue, asked once with the total estimate), list the files still in conflict, and mark a clean file resolved.
--   parse.lua   the markers and the free resolutions (pure)      git.lua   the files and the story of the merge (read-only)
--   action.lua  the request each conflict runs                    init.lua  the flows (this file)
local log = require "utils.log"
local parse = require "agent.conflict.parse"
local settings = require("core.settings").agent.conflict

local M = {}

---@param buf integer
---@return string root
local function root_of(buf)
  return vim.fs.root(buf, ".git") or vim.fn.getcwd()
end

---@param buf integer
---@return ConflictHunk[]
function M.hunks(buf)
  return parse.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

--- The conflict the cursor is in, else the next one below it, else the first
---@param hunks ConflictHunk[]
---@param row integer 1-based
---@return ConflictHunk?
function M.near(hunks, row)
  for _, h in ipairs(hunks) do
    if h.first <= row and row <= h.last then
      return h
    end
  end
  for _, h in ipairs(hunks) do
    if h.first > row then
      return h
    end
  end
  return hunks[1]
end

--- `<leader>Gxt`: resolves, with no model, every conflict where both sides agree or only one side changed anything
function M.trivial()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #parse.parse(lines) == 0 then
    return log.info "Agent: no conflict markers in this file"
  end
  local new, resolved, left = parse.resolve_trivial(lines)
  if resolved == 0 then
    return log.info(
      ("Agent: %d conflict%s here, none trivial (both sides changed the same lines differently): <leader>Gxr asks the agent"):format(
        left,
        left == 1 and "" or "s"
      )
    )
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new)
  log.info(
    left == 0 and ("Agent: %d conflict%s resolved with no model: <leader>Gxs marks the file resolved"):format(resolved, resolved == 1 and "" or "s")
      or ("Agent: %d resolved with no model, %d left (<leader>Gxr asks the agent)"):format(resolved, left)
  )
end

--- Sends the conflicts of the current file to the agent
---@param scope "here"|"all"
function M.resolve(scope)
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return log.info "Agent: this buffer has no file"
  end
  local hunks = M.hunks(buf)
  if #hunks == 0 then
    return log.info "Agent: no conflict markers in this file"
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local chosen
  if scope == "all" then
    -- the free ones first: a model is never asked about what git's own three-way logic settles
    local lines, resolved = parse.resolve_trivial(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if resolved > 0 then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      log.info(("Agent: %d conflict%s resolved with no model"):format(resolved, resolved == 1 and "" or "s"))
      hunks = M.hunks(buf)
      if #hunks == 0 then
        return log.info "Agent: that was all of them: <leader>Gxs marks the file resolved"
      end
    end
    chosen = vim.list_slice(hunks, 1, settings.max_conflicts)
  else
    chosen = { M.near(hunks, row) }
  end
  local root = root_of(buf)
  local rel = vim.fn.fnamemodify(path, ":p"):sub(#vim.fn.fnamemodify(root, ":p") + 1)
  require("agent.conflict.git").context(root, rel, function(story)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local target_mod = require "agent.context.target"
    local items = {}
    for i, h in ipairs(chosen) do
      local target, err = target_mod.of_range(buf, "lines", h.first, h.last, "conflict")
      if not target then
        log.warn(("Agent: conflict at line %d skipped: %s"):format(h.first, err))
      else
        items[#items + 1] = {
          label = ("conflict %d/%d"):format(i, #chosen),
          target = target,
          extra = {
            {
              name = "merge",
              text = ("%s\nThis conflict: ours is `%s`, theirs is `%s`."):format(story, h.ours_label, h.theirs_label),
            },
          },
        }
      end
    end
    if #items == 0 then
      return
    end
    local hl = require("utils.modal").hl
    require("agent.batch").run {
      title = "resolve conflicts",
      action = require("agent.conflict.action").build(),
      items = items,
      header = {
        {
          {
            ("%d conflict%s in %s"):format(#items, #items == 1 and "" or "s", vim.fn.fnamemodify(path, ":t")),
            hl.warn,
          },
        },
      },
      on_done = function()
        if vim.api.nvim_buf_is_valid(buf) and #M.hunks(buf) == 0 then
          log.info "Agent: no conflict is left in the file: <leader>Gxs marks it resolved"
        end
      end,
    }
  end)
end

--- `<leader>Gxf`: the files git lists as unmerged, with how many conflicts each holds
function M.files()
  local root = root_of(vim.api.nvim_get_current_buf())
  local git = require "agent.conflict.git"
  git.files(root, function(files)
    if #files == 0 then
      return log.info "Agent: no file is in conflict"
    end
    local items = {}
    for _, f in ipairs(files) do
      local ok, lines = pcall(vim.fn.readfile, f.abs)
      local hunks = ok and parse.parse(lines) or {}
      items[#items + 1] = {
        label = f.path,
        desc = #hunks == 0 and "no markers left: ready to mark resolved" or ("%d conflict%s"):format(#hunks, #hunks == 1 and "" or "s"),
        value = { file = f, first = hunks[1] and hunks[1].first or 1 },
      }
    end
    require("tasks.picker").choose(items, { title = ("Conflicted files · %d"):format(#items) }, function(v)
      vim.cmd.edit(vim.fn.fnameescape(v.file.abs))
      pcall(vim.api.nvim_win_set_cursor, 0, { v.first, 0 })
    end)
  end)
end

--- `<leader>Gxs`: `git add` of the current file once no marker is left (asks first)
function M.stage()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return
  end
  if vim.bo[buf].modified then
    return log.warn "Agent: save the file first"
  end
  if #M.hunks(buf) > 0 then
    return log.warn "Agent: conflict markers are still in the file"
  end
  local root = root_of(buf)
  local rel = vim.fn.fnamemodify(path, ":p"):sub(#vim.fn.fnamemodify(root, ":p") + 1)
  local modal = require "utils.modal"
  modal.confirm(
    { { { rel, modal.hl.file } }, { { "No conflict marker is left. Tell git it is resolved (git add)?", modal.hl.muted } } },
    { title = "Mark resolved", confirm = "git add" },
    function()
      require("agent.conflict.git").stage(root, rel, function(ok)
        log.info(ok and ("Agent: %s marked resolved"):format(rel) or "Agent: git add failed")
      end)
    end
  )
end

return M
