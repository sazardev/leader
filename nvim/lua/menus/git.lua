-- ── Git context: only in files that live inside a repository ─────────────────
local ex = require("utils.actions").ex

return {
  name = "Git",
  prefix = "G",
  where = "files inside a git repo",
  detect = function(buf)
    return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" and vim.fs.root(buf, ".git") ~= nil
  end,
  groups = { R = "release", x = "resolve" },
  maps = {
    -- conventional commits: ONE panel (commit/panel.lua) with three entry points, and `M` without a panel (commit/auto.lua)
    {
      "c",
      "commit",
      function()
        require("commit").open()
      end,
    },
    {
      "m",
      "commit + AI draft",
      function()
        require("commit").ai()
      end,
    },
    {
      "M",
      "commit auto",
      function()
        require("commit").auto()
      end,
    },
    {
      "a",
      "amend",
      function()
        require("commit").amend()
      end,
    },
    -- the staged changes, read before they become a commit (secrets and leftovers for free, the code once)
    {
      "v",
      "review staged",
      function()
        require("agent.review").run(require("commit.git").root())
      end,
    },
    -- .gitignore from what the project looks like: secrets, languages, Docker... (lua/gitignore/)
    {
      "i",
      "ignore rules",
      function()
        require("gitignore").open()
      end,
    },
    -- release (lua/release/): changelog and checklist for free, the PR description with one light request
    {
      "Rc",
      "release changelog",
      function()
        require("release").changelog()
      end,
    },
    {
      "Rp",
      "release PR description",
      function()
        require("release").pr()
      end,
    },
    {
      "Rl",
      "release checklist",
      function()
        require("release").checklist()
      end,
    },
    { "t", "status", ex "Telescope git_status" },
    { "b", "blame", ex "GitBlameToggle" },
    { "d", "diff", ex "DiffviewOpen" },
    { "f", "file history", ex "DiffviewFileHistory %" },
    { "r", "repo history", ex "DiffviewFileHistory" },
    { "q", "close diff", ex "DiffviewClose" },
    -- merge conflicts (git-conflict.nvim)
    { "o", "conflict ours", ex "GitConflictChooseOurs" },
    { "T", "conflict theirs", ex "GitConflictChooseTheirs" },
    { "B", "conflict both", ex "GitConflictChooseBoth" },
    { "N", "conflict none", ex "GitConflictChooseNone" },
    { "n", "conflict next", ex "GitConflictNextConflict" },
    { "p", "conflict previous", ex "GitConflictPrevConflict" },
    { "l", "conflict list", ex "GitConflictListQf" },
    -- merge conflicts with the agent (lua/agent/conflict/): the trivial ones for free, the rest one proposal each
    {
      "xt",
      "conflict trivial",
      function()
        require("agent.conflict").trivial()
      end,
    },
    {
      "xr",
      "conflict agent",
      function()
        require("agent.conflict").resolve "here"
      end,
    },
    {
      "xR",
      "conflict agent all",
      function()
        require("agent.conflict").resolve "all"
      end,
    },
    {
      "xf",
      "conflict files",
      function()
        require("agent.conflict").files()
      end,
    },
    {
      "xs",
      "conflict resolved",
      function()
        require("agent.conflict").stage()
      end,
    },
  },
}
