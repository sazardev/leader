-- ── GitHub: the gh CLI, its TUIs and octo.nvim ───────────────────────────────
-- Global on purpose: gh-dash and the notifications are about your account, not the folder. The actions that need a
-- repository say so (`lua/github/init.lua`). `s` installs the extensions the first time; the launch keys do it too.
return {
  name = "GitHub",
  prefix = "Gh",
  where = "everywhere (a repository for the actions that need one)",
  global = true,
  maps = {
    {
      "d",
      "dash: PRs and issues (gh-dash)",
      function()
        require("github").launch "dash"
      end,
    },
    {
      "o",
      "checks: current PR, live (gh-observer)",
      function()
        require("github").launch "observer"
      end,
    },
    {
      "e",
      "actions: runs and logs (gh-enhance)",
      function()
        require("github").launch "enhance"
      end,
    },
    {
      "n",
      "notifications (gh-news)",
      function()
        require("github").launch "news"
      end,
    },
    {
      "p",
      "PRs (octo)",
      function()
        require("github").octo "pr list"
      end,
    },
    {
      "i",
      "issues (octo)",
      function()
        require("github").octo "issue list"
      end,
    },
    {
      "r",
      "review the current PR (octo)",
      function()
        require("github").octo "review"
      end,
    },
    {
      "v",
      "open the current PR in the browser",
      function()
        require("github").run_in_repo "gh pr view --web"
      end,
    },
    {
      "c",
      "checks of the current PR",
      function()
        require("github").run_in_repo "gh pr checks"
      end,
    },
    {
      "b",
      "open the repository in the browser",
      function()
        require("github").run_in_repo "gh browse"
      end,
    },
    {
      "a",
      "auth status",
      function()
        require("github").run "gh auth status"
      end,
    },
    {
      "A",
      "auth login",
      function()
        require("github").run "gh auth login"
      end,
    },
    {
      "s",
      "setup: install the extensions",
      function()
        require("github").setup()
      end,
    },
  },
}
