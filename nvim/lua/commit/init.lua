-- ── Commits (<leader>G menu): facade ─────────────────────────────────────────
-- A single experience, the panel (commit/panel.lua), with three entry points, and a panel-less mode:
--   open()   review what is being committed, write the message (assisted type/scope) and commit
--   ai()     same, already requesting the draft from the agent (reads only what is staged; the panel says what and with which model)
--   amend()  rewrite the message of the last commit (warns if it is already on the remote)
--   auto()   no panel, in the background: stages (if needed), the AI writes ONE message and commits (commit/auto.lua)
--   commit/conventional.lua  validation and suggestions (pure) · commit/git.lua  git · commit/ai.lua  the draft
local M = {}

function M.open()
  require("commit.panel").open()
end

function M.ai()
  require("commit.panel").open { ai = true }
end

function M.auto()
  require("commit.auto").run()
end

function M.amend()
  local git = require "commit.git"
  local root = git.root()
  if not root then
    return require("utils.log").warn "Not inside a git repository"
  end
  -- rewriting a commit that others may already have breaks their history
  if git.head(root) and git.head_on_remote(root) then
    return vim.ui.select({ "Amend anyway (needs a force push later)", "Cancel" }, {
      prompt = "This commit is already on the remote",
    }, function(_, idx)
      if idx == 1 then
        require("commit.panel").open { amend = true }
      end
    end)
  end
  require("commit.panel").open { amend = true }
end

return M
