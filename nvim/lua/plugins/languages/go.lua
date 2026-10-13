-- go.nvim: not loaded in light mode (resident and heavy) and not installed if you disable Go
-- (`languages.disabled`): its `build` downloads the Go tools.
return {
  "ray-x/go.nvim",
  enabled = not vim.tbl_contains(require("core.settings").languages.disabled, "go"),
  dependencies = { "ray-x/guihua.lua" },
  ft = { "go", "gomod", "gowork" },
  cond = function()
    return not require("core.light").enabled
  end,
  build = ':lua require("go.install").update_all_sync()',
  config = function()
    -- GoAddTag: json:"sent_at" (snake_case); omitempty is requested separately (<leader>gA)
    require("go").setup { tag_transform = "snakecase", tag_options = false }
  end,
}
